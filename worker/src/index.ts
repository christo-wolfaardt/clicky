/**
 * Clicky Proxy Worker
 *
 * Proxies requests to Claude and ElevenLabs APIs so the app never
 * ships with raw API keys. Keys are stored as Cloudflare secrets.
 *
 * Routes:
 *   POST /chat                → Anthropic Messages API (streaming)
 *   POST /tts                 → ElevenLabs TTS API
 *   POST /transcribe-token    → AssemblyAI temporary token
 *   POST /verify-access-code  → Confirms an access code and returns its owner's name
 *
 * Every route requires `Authorization: Bearer <access code>`. Access codes
 * are personal (one per person) and stored in the CLICKY_USERS KV namespace
 * as SHA-256 hashes, so the raw codes never sit in Cloudflare. Manage them
 * with the scripts in worker/scripts/.
 */

interface Env {
  ANTHROPIC_API_KEY: string;
  ELEVENLABS_API_KEY: string;
  ELEVENLABS_VOICE_ID: string;
  ASSEMBLYAI_API_KEY: string;
  CLICKY_USERS: KVNamespace;
}

/** Stored at `user:<sha256 of access code>` in the CLICKY_USERS namespace. */
interface ClickyUserRecord {
  name: string;
  /** Max /chat requests per UTC day. null means unlimited. */
  dailyChatRequestLimit: number | null;
}

/** Usage counters expire on their own so the namespace doesn't grow forever. */
const USAGE_COUNTER_RETENTION_SECONDS = 60 * 60 * 24 * 45;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      const authenticatedUser = await findUserForAccessCode(request, env);
      if (!authenticatedUser) {
        return jsonResponse({ error: "invalid_access_code" }, 401);
      }

      if (url.pathname === "/verify-access-code") {
        return jsonResponse({ name: authenticatedUser.name }, 200);
      }

      if (url.pathname === "/chat") {
        const isWithinDailyLimit = await recordChatRequestIfWithinDailyLimit(authenticatedUser, env);
        if (!isWithinDailyLimit) {
          return jsonResponse({ error: "daily_limit_reached" }, 429);
        }
        return await handleChat(request, env);
      }

      if (url.pathname === "/tts") {
        return await handleTTS(request, env);
      }

      if (url.pathname === "/transcribe-token") {
        return await handleTranscribeToken(env);
      }
    } catch (error) {
      console.error(`[${url.pathname}] Unhandled error:`, error);
      return new Response(
        JSON.stringify({ error: String(error) }),
        { status: 500, headers: { "content-type": "application/json" } }
      );
    }

    return new Response("Not found", { status: 404 });
  },
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function findUserForAccessCode(request: Request, env: Env): Promise<ClickyUserRecord | null> {
  const authorizationHeader = request.headers.get("authorization") ?? "";
  const bearerPrefix = "Bearer ";
  if (!authorizationHeader.startsWith(bearerPrefix)) {
    return null;
  }

  const accessCode = authorizationHeader.slice(bearerPrefix.length).trim();
  if (accessCode.length === 0) {
    return null;
  }

  const accessCodeHash = await sha256Hex(accessCode);
  return await env.CLICKY_USERS.get<ClickyUserRecord>(`user:${accessCodeHash}`, "json");
}

/**
 * Counts this /chat request against the user's daily limit. Only /chat is
 * counted because it's the expensive call (Claude with screenshots); TTS and
 * transcription tokens always follow a chat turn.
 *
 * KV has no atomic increment, so two requests landing at the same instant can
 * both read the same count. For a handful of family users that slack is fine.
 */
async function recordChatRequestIfWithinDailyLimit(user: ClickyUserRecord, env: Env): Promise<boolean> {
  const todayInUTC = new Date().toISOString().slice(0, 10);
  const usageCounterKey = `usage:${user.name}:${todayInUTC}`;
  const chatRequestsSoFarToday = parseInt((await env.CLICKY_USERS.get(usageCounterKey)) ?? "0", 10);

  if (user.dailyChatRequestLimit !== null && chatRequestsSoFarToday >= user.dailyChatRequestLimit) {
    return false;
  }

  await env.CLICKY_USERS.put(usageCounterKey, String(chatRequestsSoFarToday + 1), {
    expirationTtl: USAGE_COUNTER_RETENTION_SECONDS,
  });
  return true;
}

async function handleChat(request: Request, env: Env): Promise<Response> {
  const body = await request.text();

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/chat] Anthropic API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "text/event-stream",
      "cache-control": "no-cache",
    },
  });
}

async function handleTranscribeToken(env: Env): Promise<Response> {
  const response = await fetch(
    "https://streaming.assemblyai.com/v3/token?expires_in_seconds=480",
    {
      method: "GET",
      headers: {
        authorization: env.ASSEMBLYAI_API_KEY,
      },
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/transcribe-token] AssemblyAI token error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const data = await response.text();
  return new Response(data, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function handleTTS(request: Request, env: Env): Promise<Response> {
  const body = await request.text();
  const voiceId = env.ELEVENLABS_VOICE_ID;

  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY,
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body,
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/tts] ElevenLabs API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "audio/mpeg",
    },
  });
}
