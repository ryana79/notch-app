//
//  NotchProHeader.swift
//  notchpro
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

struct NotchCollapseHandle: View {
    @EnvironmentObject var vm: NotchProViewModel
    @State private var dragOffset: CGFloat = 0

    private let closeSpring = Animation.spring(response: 0.52, dampingFraction: 0.86, blendDuration: 0.15)

    var body: some View {
        VStack(spacing: 2) {
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 34, height: 4)
            Image(systemName: "chevron.compact.up")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.vertical, 4)
        .offset(y: dragOffset)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    dragOffset = min(0, value.translation.height * 0.35)
                }
                .onEnded { value in
                    if value.translation.height < -18 {
                        dismissNotch()
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        dragOffset = 0
                    }
                }
        )
        .onTapGesture {
            dismissNotch()
        }
        .help("Swipe up or click to collapse")
    }

    private func dismissNotch() {
        guard !SharingStateManager.shared.preventNotchClose else { return }
        withAnimation(closeSpring) {
            vm.close()
        }
    }
}

struct NotchProHeader: View {
    @EnvironmentObject var vm: NotchProViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = NotchProCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            if vm.notchState == .open {
                NotchCollapseHandle()
            }

            HStack(spacing: 0) {
                HStack {
                    if (!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.notchProShelf] {
                        TabSelectionView()
                    } else if vm.notchState == .open {
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(vm.notchState == .closed ? 0 : 1)
                .blur(radius: vm.notchState == .closed ? 20 : 0)
                .zIndex(2)

                if vm.notchState == .open {
                    Rectangle()
                        .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                        .frame(width: vm.closedNotchSize.width)
                        .mask {
                            NotchShape()
                        }
                }

                HStack(spacing: 4) {
                    if vm.notchState == .open {
                        if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                            OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    if Defaults[.showMirror] {
                                        Button(action: {
                                            vm.toggleCameraPreview()
                                        }) {
                                            Capsule()
                                                .fill(.black)
                                                .frame(width: 30, height: 30)
                                                .overlay {
                                                    Image(systemName: "web.camera")
                                                        .foregroundColor(.white)
                                                        .padding()
                                                        .imageScale(.medium)
                                                }
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                    if Defaults[.settingsIconInNotch] {
                                        Button(action: {
                                            DispatchQueue.main.async {
                                                SettingsWindowController.shared.showWindow()
                                            }

                                        }) {
                                            Capsule()
                                                .fill(.black)
                                                .frame(width: 30, height: 30)
                                                .overlay {
                                                    Image(systemName: "gear")
                                                        .foregroundColor(.white)
                                                        .padding()
                                                        .imageScale(.medium)
                                                }
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                    if Defaults[.showBatteryIndicator] {
                                        NotchProBatteryView(
                                            batteryWidth: 30,
                                            isCharging: batteryModel.isCharging,
                                            isInLowPowerMode: batteryModel.isInLowPowerMode,
                                            isPluggedIn: batteryModel.isPluggedIn,
                                            levelBattery: batteryModel.levelBattery,
                                            maxCapacity: batteryModel.maxCapacity,
                                            timeToFullCharge: batteryModel.timeToFullCharge,
                                            isForNotification: false
                                        )
                                    }
                                    WeatherGlanceView()
                                    PortfolioGlanceView()
                                    WorkoutGlanceView()
                                    NotchCalendarGlance()
                                    FocusTimerGlance()
                                    SystemStatsGlance()
                                }
                            }

                            Button {
                                ApplicationRelauncher.quitCompletely()
                            } label: {
                                NotchProPill(tint: .red) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "power")
                                            .font(.caption2)
                                        Text("Quit")
                                            .font(.caption2.weight(.semibold))
                                    }
                                    .foregroundStyle(.white.opacity(0.9))
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Quit NotchPro completely")
                            .layoutPriority(1)
                        }
                    }
                }
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(vm.notchState == .closed ? 0 : 1)
                .blur(radius: vm.notchState == .closed ? 20 : 0)
                .zIndex(2)
            }
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    NotchProHeader().environmentObject(NotchProViewModel())
}
