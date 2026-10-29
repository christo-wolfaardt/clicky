# Clicky

A screen-aware AI buddy that lives next to your cursor on macOS. Hold **Control + Option**, ask a question out loud, and Clicky looks at your screen, answers with a voice, and can point at things.

Based on the open-source [Clicky](https://github.com/farzaa/clicky) by Farza (MIT). This version removes the original author's analytics, email capture and update feed, and adds personal sign-in so one server can be shared with family and friends.

## How it fits together

```
Clicky.app ──(access code)──▶ Cloudflare Worker ──(your API keys)──▶ Anthropic · AssemblyAI · ElevenLabs
```

- **The server** (`worker/`) is a small Cloudflare Worker that holds the API keys. Whoever runs it pays for usage.
- **The app** never contains keys or server details. People sign in with a server address and a personal access code, or with their own API keys.
- **Access codes** are per person, with an optional daily limit and model allowlist, and can be revoked at any time.

## If you're running the server

You need a free [Cloudflare](https://dash.cloudflare.com) account, Node.js 18+, and API keys for [Anthropic](https://console.anthropic.com), [AssemblyAI](https://www.assemblyai.com) and [ElevenLabs](https://elevenlabs.io).

```bash
cd worker
npm install
npx wrangler login

# Once: create the access-code store and paste its id into wrangler.toml
npx wrangler kv namespace create CLICKY_USERS

# Also set ELEVENLABS_VOICE_ID in wrangler.toml, then add your keys
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY

npx wrangler deploy        # prints your server address
```

Manage who can use it:

```bash
node scripts/add-user.mjs christo                                  # unlimited, any model
node scripts/add-user.mjs eben 50 --models claude-sonnet-4-6       # 50 chats/day, Sonnet only
node scripts/show-usage.mjs
node scripts/remove-user.mjs eben
```

Send each person their access code and your server address. Set a monthly spend limit in the Anthropic console as a backstop.

## If you're using the app

Open Clicky from the menu bar and sign in one of two ways:

- **Clicky server**: the server address and access code you were given.
- **My own API keys**: paste your own keys; nobody else's server is involved. Only an Anthropic key is required. Without AssemblyAI, Apple's speech recognition is used; without ElevenLabs, the built-in macOS voice speaks.

Grant the permissions it asks for, then hold **Control + Option** to talk.

## Building the app

Requires macOS 14.2+ and Xcode 15+.

1. `open leanring-buddy.xcodeproj`
2. Select the `leanring-buddy` target → **Signing & Capabilities** → choose your team and a unique bundle identifier.
3. **Cmd + R**.

Don't build with `xcodebuild` from the terminal; it resets the app's screen recording and accessibility permissions.

See `CLAUDE.md` for architecture and code conventions.

## License

MIT. See `LICENSE`.
