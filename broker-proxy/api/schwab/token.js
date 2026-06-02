/**
 * NotchPro Schwab token proxy — keeps Client Secret off friends' Macs.
 *
 * Env vars (Vercel):
 *   SCHWAB_CLIENT_ID
 *   SCHWAB_CLIENT_SECRET
 *   NOTCHPRO_BROKER_PROXY_KEY  (shared with BrokerCredentials.plist)
 */

const SCHWAB_TOKEN_URL = "https://api.schwabapi.com/v1/oauth/token";

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

  const clientId = process.env.SCHWAB_CLIENT_ID;
  const clientSecret = process.env.SCHWAB_CLIENT_SECRET;
  if (!clientId || !clientSecret) {
    res.status(500).json({ error: "Schwab credentials not configured on server" });
    return;
  }

  const body = typeof req.body === "string" ? JSON.parse(req.body) : req.body;
  const grantType = body.grant_type;
  if (!grantType) {
    res.status(400).json({ error: "grant_type required" });
    return;
  }

  const params = new URLSearchParams();
  params.set("grant_type", grantType);

  if (grantType === "authorization_code") {
    if (!body.code || !body.redirect_uri) {
      res.status(400).json({ error: "code and redirect_uri required" });
      return;
    }
    params.set("code", body.code);
    params.set("redirect_uri", body.redirect_uri);
  } else if (grantType === "refresh_token") {
    if (!body.refresh_token) {
      res.status(400).json({ error: "refresh_token required" });
      return;
    }
    params.set("refresh_token", body.refresh_token);
  } else {
    res.status(400).json({ error: "Unsupported grant_type" });
    return;
  }

  const basic = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");

  try {
    const upstream = await fetch(SCHWAB_TOKEN_URL, {
      method: "POST",
      headers: {
        Authorization: `Basic ${basic}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: params.toString(),
    });

    const text = await upstream.text();
    res.status(upstream.status).setHeader("Content-Type", "application/json").send(text);
  } catch (err) {
    res.status(502).json({ error: "Schwab token exchange failed", detail: String(err) });
  }
};
