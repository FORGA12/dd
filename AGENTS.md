# AGENTS.md — Orientation for AI Agents

This file helps AI coding agents (Claude Code, Codex, Copilot, etc.) understand this repository quickly and avoid breaking its carefully-tuned behavior.

## What this repo is

FreeDeepseekAPI is a **zero-dependency Node.js proxy** that exposes DeepSeek's free Web Chat (`chat.deepseek.com`) as OpenAI-, Anthropic-, and Responses-compatible local API endpoints. The browser-facing internals were reverse-engineered: the proxy solves a SHA3 WASM proof-of-work challenge, creates chat sessions, streams SSE from DeepSeek, and translates between protocols.

**The one thing that must never break:** the tool-calling handshake with agent clients (especially Claude Code). It is prompt-emulated and guarded by several mechanisms (below). Treat every one of them as load-bearing.

## File map

| File | Role |
| --- | --- |
| `server.js` | The whole proxy: HTTP server, DeepSeek Web client (PoW, sessions, streaming), OpenAI/Anthropic/Responses protocol conversion, tool-call parsing, session pool, account pool, reliability guards. ~2,700 lines. |
| `lib/pow.js` | SHA3 WASM PoW solver shared by server and CLI client (compiled-module cache + fetch timeout). |
| `client.js` | Minimal CLI client that talks to DeepSeek Web directly (not through the proxy). |
| `scripts/auth.js` | Interactive auth menu (login / import / status / remove). |
| `scripts/auth_import.js` | Import a `deepseek-auth.json` or browser cookie export. |
| `scripts/deepseek_chrome_auth.js` | Chrome CDP automation for the login flow. |
| `scripts/doctor.js` | Diagnostics: auth file validity, permissions, live PoW reachability. |
| `scripts/probe_deepseek_models.js` | Probes DeepSeek Web model modes (`default`, `expert`, `vision` × thinking × search). |
| `scripts/live_agentic_smoke_tests.mjs` | Live end-to-end tests against a running proxy (needs real auth + network). |
| `tests/unit.test.js` | Node's built-in test runner; covers parsers, prompt builders, recovery logic. |
| `chrome-extension/` | Optional browser extension for auth/cookies. |
| `docs/api-documentation.md` | Full API + architecture documentation. |
| `.env.example` | All configuration variables with comments. |

## Core concepts

### 1. Prompt-emulated tool calling (the heart of the project)

DeepSeek Web has **no native tool API**. The proxy:

1. Injects tool definitions into the system prompt via `formatToolDefinitions()` (strict-JSON envelope + few-shot example + anti-refusal clauses).
2. Appends `TOOL_TAIL_REMINDER` to the end of every tool-bearing turn so compliance survives long contexts.
3. Parses the model's text with `parseToolCall()` — supports strict JSON `{"tool_call":{...}}`, `TOOL_CALL: name`, fenced JSON envelopes, XML-ish `<tool_call>`, and DeepSeek DSML.
4. Maps a parsed call to `finish_reason: 'tool_calls'` (→ Anthropic `stop_reason: 'tool_use'`) so the client executes it.

### 2. Agent-reliability guards (do NOT remove or weaken)

These exist because DeepSeek frequently *narrates* intent ("I'll do X…") or *refuses* instead of emitting a tool call, which makes agent clients stop and return control to the user:

- **Narration/refusal detector** — `looksLikeToolIntentWithoutCall(text)`: matches "I'll / I will / Let me / I'm going to / I am going to / I'd / I would" + action verbs, "I can't", "I don't have access", "As an AI", truncated intents ending in `:` or `…`. When tools were offered and this fires, the proxy re-prompts the model up to 2 times (showing it its own prose) before giving up.
- **Tool-failure reminder** — when the latest tool result indicates failure ("error while loading shared libraries", "Failed to launch", "cannot open", …), the proxy injects a `[TOOL FAILURE]` block telling the model to keep working instead of stopping.
- **Loop breaker** — `findRepeatedToolCallLoop()`: when the same tool call (name + arguments) appears 3+ times in a row, the proxy injects a `[LOOP WARNING]` telling the model to stop repeating.
- **Transient/rate-limit retries** — `isRateLimitModelError()` / `isTransientModelError()` classify DeepSeek's 200-SSE `error` events (including Russian-language messages) so the recovery loop retries with backoff instead of giving up; exhausted retries classify as HTTP 429 `rate_limit_error` with `Retry-After`.

**Invariant:** malformed tool-call markup must never leak to the client as plain text — retry or fail loudly (502 `malformed_tool_call`), never silently downgrade to `end_turn` when tools were expected.

### 3. Sessions and accounts

- One `x-agent-session` / `user` → one DeepSeek chat session, continued via `parent_message_id`.
- Sessions auto-reset on TTL, errors, or over-long chains; recovery history is injected only when the client didn't already send multi-turn history.
- Multi-account pool: sticky account per session, cooldown on `401/403/429`, `/health` reports status without paths or file names.
- Empty responses are retried up to `DEEPSEEK_MAX_RETRIES` times with shrinking context.

### 4. Configuration

Everything lives in `.env.example` — read it before changing behavior. Notable knobs: `DEEPSEEK_AUTH_PATH`/`DEEPSEEK_AUTH_DIR`, `DEEPSEEK_ACCOUNT_COOLDOWN_MS`, `DEEPSEEK_MAX_PROMPT_CHARS`, `DEEPSEEK_MAX_RETRIES`, `NON_INTERACTIVE`, `PROXY_API_KEY`, `DEEPSEEK_INJECT_MEDIA` (a Telegram helper, **off** by default — keep it off for agent clients).

## Development workflow

```bash
npm test                    # syntax checks + unit tests (node --test)
npm run doctor -- --offline # auth/health check without network
```

Live testing (requires valid `deepseek-auth.json` + network):

```bash
NON_INTERACTIVE=1 npm start                      # start proxy on :9655
BASE_URL=http://127.0.0.1:9655 MODEL=deepseek-chat npm run test:live
```

When you change prompt builders (`formatToolDefinitions`, `TOOL_TAIL_REMINDER`, fallback prompts) or the parser, **add/update unit tests** — the exact prompt text is asserted in `tests/unit.test.js`, and behavior is verified live via the smoke tests.

## Security rules (hard requirements)

- **Never commit** `deepseek-auth*.json`, `auth.json`, `deepseek-accounts.json`, `data/accounts/*.json`, `.env`, Chrome profile dirs, or any file containing live tokens/cookies. They are gitignored; keep them that way.
- `deepseek-auth.json` is a full DeepSeek Web login — treat it as a password.
- Never log tokens, cookies, or full auth contents. The repo already redacts these.
- API keys (`PROXY_API_KEY`) belong in env vars or Podman secrets, never in code or README.

## Common gotchas

- `x-client-locale: 'en'` + English headers are intentional; DeepSeek error messages may arrive in Russian — the classifiers match both languages, keep that.
- `x-client-version: '2.0.0'` is required for the `expert` web mode — don't "simplify" headers.
- The Anthropic shim filters tools through `normalizeAnthropicTools`; sending OpenAI-format tools to `/v1/messages` silently drops them (a classic debugging trap).
- `reasoning_content` must be stripped from tool-call turns — some agent clients treat any text payload as a final answer and stop their tool loop.
- The server is single-file and large; search with `code_search` and read focused windows rather than loading it whole.
