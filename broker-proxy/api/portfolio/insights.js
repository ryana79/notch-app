/**
 * NotchPro portfolio insights proxy — shared Groq key for all users.
 *
 * Env vars (Vercel):
 *   GROQ_API_KEY
 *   NOTCHPRO_BROKER_PROXY_KEY
 */

const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";

module.exports = async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const apiKey = req.headers["x-notchpro-key"];
  if (!process.env.NOTCHPRO_BROKER_PROXY_KEY || apiKey !== process.env.NOTCHPRO_BROKER_PROXY_KEY) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }

  const groqKey = process.env.GROQ_API_KEY;
  if (!groqKey) {
    res.status(503).json({ error: "AI insights not configured on server" });
    return;
  }

  const body = typeof req.body === "string" ? JSON.parse(req.body) : req.body;
  const prompt = body.prompt;
  if (!prompt || typeof prompt !== "string") {
    res.status(400).json({ error: "prompt required" });
    return;
  }

  try {
    const upstream = await fetch(GROQ_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${groqKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "llama-3.3-70b-versatile",
        messages: [
          { role: "system", content: "You are a helpful portfolio analyst. Be factual and concise." },
          { role: "user", content: prompt },
        ],
        max_tokens: typeof body.max_tokens === "number" ? body.max_tokens : 350,
        temperature: 0.35,
      }),
    });

    const text = await upstream.text();
    res.status(upstream.status).setHeader("Content-Type", "application/json").send(text);
  } catch (err) {
    res.status(502).json({ error: "Insights request failed", detail: String(err) });
  }
};
