//
//  SystemStatsManager.swift
//  NotchPro
//

import Combine
import Defaults
import Foundation

@MainActor
final class SystemStatsManager: ObservableObject {
    static let shared = SystemStatsManager()

    @Published private(set) var cpuPercent: Int = 0
    @Published private(set) var memoryUsedMB: Int = 0
    @Published private(set) var memoryTotalMB: Int = 0

    private var pollTimer: Timer?

    var memoryPercent: Int {
        guard memoryTotalMB > 0 else { return 0 }
        return Int((Double(memoryUsedMB) / Double(memoryTotalMB)) * 100)
    }

    private init() {}

    func startIfEnabled() {
        guard Defaults[.showSystemStats] else {
            stop()
            return
        }
        refresh()
        pollTimer?.invalidate()
        let interval = Defaults[.performanceMode] ? 12.0 : 5.0
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refreshIfEnabled() {
        guard Defaults[.showSystemStats] else { return }
        startIfEnabled()
    }

    private func refresh() {
        cpuPercent = Self.readCPUPercent()
        let (used, total) = Self.readMemory()
        memoryUsedMB = used
        memoryTotalMB = total
    }

    private static func readMemory() -> (Int, Int) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let pageSize = Int(vm_kernel_page_size)
        let used = Int(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize / 1_048_576
        let total = Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
        return (used, total)
    }

    private static func readCPUPercent() -> Int {
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCpus, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS else { return 0 }

        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        var totalUser: Int64 = 0, totalSystem: Int64 = 0, totalIdle: Int64 = 0
        for i in 0..<Int(numCpus) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser += Int64(cpuInfo[offset + Int(CPU_STATE_USER)])
            totalSystem += Int64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            totalIdle += Int64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
        }
        let total = totalUser + totalSystem + totalIdle
        guard total > 0 else { return 0 }
        return Int(((totalUser + totalSystem) * 100) / total)
    }
}
