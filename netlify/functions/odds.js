// Proxies requests to The Odds API. The API key lives only in Netlify's
// environment variables (ODDS_API_KEY) and is never sent to the browser.
exports.handler = async (event) => {
  const key = process.env.ODDS_API_KEY;
  if (!key) {
    return { statusCode: 500, body: JSON.stringify({ error: "ODDS_API_KEY is not set on the server" }) };
  }

  const sport = event.queryStringParameters && event.queryStringParameters.sport;
  if (!sport) {
    return { statusCode: 400, body: JSON.stringify({ error: "Missing sport parameter" }) };
  }

  const url = `https://api.the-odds-api.com/v4/sports/${encodeURIComponent(sport)}/odds/?apiKey=${encodeURIComponent(key)}&regions=uk,eu&markets=h2h&oddsFormat=decimal`;

  try {
    const res = await fetch(url);
    const body = await res.text();
    return {
      statusCode: res.status,
      headers: { "Content-Type": "application/json" },
      body
    };
  } catch (err) {
    return { statusCode: 502, body: JSON.stringify({ error: "Upstream fetch failed", detail: String(err) }) };
  }
};
