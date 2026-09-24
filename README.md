# FreeDeepseekAPI

<p align="center">
  <strong>Run DeepSeek Web Chat as a free, local, OpenAI-compatible API — with Anthropic & Responses shims for Claude Code and modern agent clients.</strong>
</p>

<p align="center">
  <a href="https://github.com/qaderizadeh/FreeDeepseekAPI/blob/main/LICENSE"><img alt="License MIT" src="https://img.shields.io/badge/license-MIT-green.svg" /></a>
  <img alt="Node.js 18+" src="https://img.shields.io/badge/node-18%2B-339933.svg" />
  <img alt="Zero npm dependencies" src="https://img.shields.io/badge/dependencies-0-blue.svg" />
  <img alt="OpenAI compatible" src="https://img.shields.io/badge/OpenAI-compatible-111111.svg" />
  <img alt="Anthropic compatible" src="https://img.shields.io/badge/Anthropic-compatible-D97757.svg" />
  <img alt="Docker / Podman" src="https://img.shields.io/badge/containers-Podman%20%2F%20Docker-2496ED.svg" />
</p>

<p align="center">
  <a href="#-features">Features</a> •
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-claude-code">Claude Code</a> •
  <a href="#-models">Models</a> •
  <a href="#-endpoints">Endpoints</a> •
  <a href="#-docs">Docs</a>
</p>

---

FreeDeepseekAPI turns your free **DeepSeek Web Chat** account (`chat.deepseek.com`) into a local API server. It speaks the OpenAI Chat Completions protocol natively and ships shims for the **Anthropic Messages API** (Claude Code) and the **OpenAI Responses API** (Codex-style clients), so you can plug DeepSeek's free web model into Open WebUI, LiteLLM, Hermes, Claude Code, and any OpenAI-compatible tooling.

The proxy authenticates with your regular logged-in DeepSeek account in a dedicated Chrome profile, then drives the internal DeepSeek Web API — proof-of-work challenges, chat sessions, streaming — all behind a clean HTTP interface.

> ⚠️ This is an experimental web-chat proxy. DeepSeek can change its internal Web API at any time. For production workloads, the official paid DeepSeek API remains the reliable option.

---

## ✨ Features

- **OpenAI-compatible API** — `POST /v1/chat/completions`
- **Anthropic Messages shim** — `POST /v1/messages` (Claude Code, Anthropic SDK)
- **OpenAI Responses shim** — `POST /v1/responses` (new OpenAI/Codex-style clients)
- **Streaming** — SSE chunks and plain non-stream JSON responses
- **Reasoning output** — separate `reasoning_content` for thinking models
- **Tool calling** — parses OpenAI, Anthropic, and Responses function tools, with prompt-emulated tool calling for DeepSeek Web
- **Agent reliability** — tail tool reminder, narration/refusal re-prompt fallback, tool-failure recovery, and repeated-call loop breaker keep agentic sessions on track
- **Model capabilities** — `GET /v1/model-capabilities` maps aliases → real web modes
- **Agent sessions** — one isolated DeepSeek session per `user` / agent id, with auto-reset and history recovery
- **Multi-account pool** — sticky accounts per session, cooldowns, graceful failover
- **Zero dependencies** — Node.js 18+, no npm packages
- **Container-ready** — hardened rootless Podman / Docker image

---

## ⚡ Quick Start

```bash
git clone https://github.com/qaderizadeh/FreeDeepseekAPI.git
cd FreeDeepseekAPI
npm run auth
npm start
```

`npm run auth` opens the auth helper:

1. Choose `1` — Log in / refresh DeepSeek login
2. A dedicated Chrome window opens — sign in to DeepSeek
3. Send a short test message (e.g. `ok`) in that window
4. Return to the terminal and press Enter

`npm start` shows the startup menu:

- `1` — log in / refresh DeepSeek login
- `2` — show models and statuses
- `3` — start the proxy (default)
- `4` — exit

For headless / CI startup without the menu:

```bash
NON_INTERACTIVE=1 npm start
# or
SKIP_ACCOUNT_MENU=1 npm start
```

The server listens on:

```text
http://localhost:9655
```

By default the proxy is bound to loopback only. To expose it to the network, set a host **and** a proxy API key:

```bash
HOST=0.0.0.0 PROXY_API_KEY='replace-with-a-long-random-value' npm start
```

Clients then authenticate with `Authorization: Bearer <key>`. Without `PROXY_API_KEY`, non-health endpoints stay unauthenticated — never publish such an instance to the network.

Browser-origin requests are allowed from loopback only. If a UI runs elsewhere, add its exact origin as a comma-separated allowlist:

```bash
PROXY_CORS_ORIGINS=https://ui.example.com,http://192.168.1.20:3000 npm start
```

---

## 🖥 Claude Code

Point Claude Code directly at the proxy:

```bash
export ANTHROPIC_BASE_URL="http://127.0.0.1:9655"
export ANTHROPIC_AUTH_TOKEN="dummy-key"
export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1
claude --model deepseek-chat
```

Recommended models: `deepseek-v4-pro` (Expert + reasoning — most reliable for agentic loops) or `deepseek-reasoner`. The proxy injects a compact tool reminder at the end of every turn and actively guards against the common agent failure modes: narration without a tool call, refusals, repeated identical tool calls, and stopping after a tool failure.

---

## 🧠 Models

`GET /v1/models` returns only aliases that are currently verified to work through this proxy.

### Working aliases

| Alias | Web mode | Reasoning | Web search | Notes |
| --- | --- | --- | --- | --- |
| `deepseek-chat` | Fast (`default`) | no | no | base chat |
| `deepseek-v3` | Fast (`default`) | no | no | compatible alias |
| `deepseek-default` | Fast (`default`) | no | no | compatible alias |
| `deepseek-reasoner` | Fast (`default`) | yes | no | `thinking_enabled=true` |
| `deepseek-r1` | Fast (`default`) | yes | no | R1-compatible alias |
| `deepseek-chat-search` | Fast (`default`) | no | yes | web search |
| `deepseek-default-search` | Fast (`default`) | no | yes | web search alias |
| `deepseek-reasoner-search` | Fast (`default`) | yes | yes | reasoning + search |
| `deepseek-r1-search` | Fast (`default`) | yes | yes | R1-compatible + search |
| `deepseek-expert` | Expert (`expert`) | no | no | Expert mode |
| `deepseek-v4-pro` | Expert (`expert`) | yes | no | Expert + reasoning |

Full mapping:

```bash
curl http://localhost:9655/v1/model-capabilities
```

Per the official DeepSeek V4 Preview page, `deepseek-chat` and `deepseek-reasoner` currently route to `deepseek-v4-flash` (non-thinking / thinking). The proxy reports both the web mode (`default` / Fast) and the current official routing (`DeepSeek-V4-Flash`).

- `default` (UI: Fast) — works; supports `thinking_enabled` and `search_enabled`.
- `expert` (UI: Expert) — works via the current web contract (`x-client-version=2.0.0`); supports `thinking_enabled`. Exposed as `deepseek-expert` (no reasoning) and `deepseek-v4-pro` (Expert + reasoning).
- `vision` (UI: Recognition) — visible in remote config but the direct Web API currently returns `backend_err_by_model`, so `deepseek-vision` stays hidden.

Web search is not available for Expert mode in the remote config, so `deepseek-expert-search` remains unsupported.

---

## 🔌 Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/` or `/health` | proxy status |
| `GET` | `/v1/models` | list working OpenAI-compatible aliases |
| `GET` | `/v1/model-capabilities` | full alias → real model / capability mapping |
| `POST` | `/v1/chat/completions` | OpenAI-compatible Chat Completions |
| `POST` | `/v1/messages` | Anthropic Messages API shim |
| `POST` | `/v1/responses` | OpenAI Responses API shim |
| `GET` | `/v1/sessions` | active local agent sessions |
| `POST` | `/reset-session?agent=<id>` | reset one session |
| `POST` | `/reset-session?agent=all` | reset all sessions |

---

## 🧪 Example Requests

### Chat Completions

```bash
curl -X POST http://localhost:9655/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-chat",
    "messages": [{"role": "user", "content": "Hello! Reply in one sentence."}],
    "stream": false
  }'
```

### Reasoning

```bash
curl -X POST http://localhost:9655/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-reasoner",
    "messages": [{"role": "user", "content": "Briefly: why is the sky blue?"}],
    "stream": false
  }'
```

Reasoning models return the chain of thought separately from the final answer:

- non-stream: `choices[0].message.reasoning_content`
- stream: `choices[0].delta.reasoning_content`
- usage: `usage.completion_tokens_details.reasoning_tokens`

`reasoning_tokens` is an approximation derived from the extracted DeepSeek Web `THINK` text.

### Web search

```bash
curl -X POST http://localhost:9655/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-chat-search",
    "messages": [{"role": "user", "content": "Find a recent fact about DeepSeek and reply briefly."}],
    "stream": false
  }'
```

### Streaming

```bash
curl -N -X POST http://localhost:9655/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-chat",
    "messages": [{"role": "user", "content": "Tell me a short joke."}],
    "stream": true
  }'
```

### Anthropic Messages API

```bash
curl -X POST http://localhost:9655/v1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-chat",
    "max_tokens": 512,
    "messages": [{"role": "user", "content": "Reply exactly OK"}],
    "stream": false
  }'
```

### OpenAI Responses API

```bash
curl -X POST http://localhost:9655/v1/responses \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-chat",
    "input": "Reply exactly OK",
    "stream": false
  }'
```

### Tool calling

The proxy accepts OpenAI `tools`, Anthropic `tools`, and Responses API function tools. Because DeepSeek Web has no native tool API, the proxy prompt-emulates tool calling and parses the model's output. Supported formats:

- strict JSON: `{"tool_call":{"name":"...","arguments":{...}}}`
- legacy: `TOOL_CALL: name` + `arguments: {...}`
- fenced JSON with a `tool_call` / `tool_calls` / `function_call` envelope
- XML-ish `<tool_call>...</tool_call>`
- DeepSeek DSML (`<｜DSML｜tool_calls>...`) and the doubled-bar Web variant

---

## 👥 Multi-Account Pool

Connect several auth files for failover and rate-limit resilience. The model is *sticky account per agent/session* — the proxy never switches accounts mid-session.

Option 1 — directory of auth files:

```bash
mkdir -p accounts
cp deepseek-auth-main.json accounts/main.json
cp deepseek-auth-backup.json accounts/backup.json
chmod 600 accounts/*.json
DEEPSEEK_AUTH_DIR=./accounts NON_INTERACTIVE=1 npm start
```

Option 2 — comma-separated file list:

```bash
DEEPSEEK_AUTH_PATH="./accounts/main.json,./accounts/backup.json" NON_INTERACTIVE=1 npm start
```

How the pool works:

- a new agent/session gets an available account round-robin;
- the chosen account is pinned to the session (`sticky`);
- on `401`, `403`, or `429` the account enters cooldown;
- if a session's sticky account is cooling down, the old DeepSeek session is reset so it never hammers a rate-limited account;
- account status is visible in `/health` (no paths or file names);
- auth files should be kept with `0600` permissions.

Cooldown tuning:

```bash
DEEPSEEK_ACCOUNT_COOLDOWN_MS=600000 npm start
```

---

## ♻️ Session Reuse & Chat Reset

FreeDeepseekAPI does not create a new DeepSeek chat for every request without reason:

- one `x-agent-session`, `session`, or `user` → one DeepSeek chat session;
- existing session ids are reused and continued via `parent_message_id`;
- auto-reset happens on TTL, DeepSeek session errors, or over-long message chains;
- local history is kept as a compact context so a fresh DeepSeek session can continue the conversation;
- long agent requests are capped at `DEEPSEEK_MAX_PROMPT_CHARS` (default 80 000 chars) — the task head, fresh tool results, and the tool adapter survive;
- if the client already sent multi-turn history, the local recovery history is not injected a second time;
- empty responses are retried up to `DEEPSEEK_MAX_RETRIES` times (default 2), shrinking context on each retry.

Set an explicit agent/session:

```bash
curl -X POST http://localhost:9655/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "x-agent-session: my-agent" \
  -d '{"model":"deepseek-chat","messages":[{"role":"user","content":"Hello"}]}'
```

List active sessions:

```bash
curl http://localhost:9655/v1/sessions
```

Reset one session:

```bash
curl -X POST "http://localhost:9655/reset-session?agent=my-agent"
```

Reset all sessions:

```bash
curl -X POST "http://localhost:9655/reset-session?agent=all"
```

---

## 🐧 Linux / Windows / VPS

**Linux / Chromium:**

```bash
git clone https://github.com/qaderizadeh/FreeDeepseekAPI.git
cd FreeDeepseekAPI
CHROME_PATH=$(which chromium) npm run auth
npm start
```

**Windows (PowerShell):**

```powershell
git clone https://github.com/qaderizadeh/FreeDeepseekAPI.git
cd FreeDeepseekAPI
npm run auth
npm start
```

If Chrome is installed in a non-standard location, set `CHROME_PATH` explicitly. When Chrome is not found, `npm run auth` prints ready-made instructions instead of a stack trace.

**VPS / headless:**

1. On a machine with a GUI, run `npm run auth`.
2. Copy the auth file to the server:

```bash
scp deepseek-auth.json user@your-vps:/opt/FreeDeepseekAPI/deepseek-auth.json
```

3. Import and verify on the server:

```bash
cd /opt/FreeDeepseekAPI
npm run auth:import -- --input ./deepseek-auth.json
npm run doctor -- --offline
```

4. Start the proxy headless:

```bash
NON_INTERACTIVE=1 npm start
```

> 🔒 `deepseek-auth.json` is your DeepSeek Web login — never commit it, never publish it, keep it at `0600`.

---

## 🦭 Rootless Podman / Docker

The container is for non-interactive proxy startup only. Run browser auth on the host with `npm run auth` — auth scripts and `deepseek-auth.json` are not copied into the image.

```bash
podman build --tag localhost/free-deepseek-api:local --file Containerfile .

podman secret create --replace free-deepseek-auth ./deepseek-auth.json
printf 'Proxy API key: '; IFS= read -r -s PROXY_API_KEY; printf '\n'
printf '%s' "$PROXY_API_KEY" | podman secret create --replace free-deepseek-proxy-key -

podman run --detach \
  --name free-deepseek-api \
  --publish 127.0.0.1:9655:9655 \
  --secret free-deepseek-auth,target=deepseek-auth.json,uid=1000,gid=1000,mode=0400 \
  --secret free-deepseek-proxy-key,target=proxy-api-key,uid=1000,gid=1000,mode=0400 \
  --read-only \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  localhost/free-deepseek-api:local
```

The image presets `NON_INTERACTIVE=1`, `HOST=0.0.0.0`, and both secret paths; `REQUIRE_PROXY_API_KEY=1` prevents startup when the key secret is missing or empty. The port is published on `127.0.0.1` only — keep it that way without a dedicated firewall/access policy.

```bash
podman healthcheck run free-deepseek-api
curl --fail http://127.0.0.1:9655/readyz
curl --fail -H "Authorization: Bearer $PROXY_API_KEY" http://127.0.0.1:9655/v1/models
```

---

## 🩺 Diagnostics

```bash
npm run doctor
# skip network checks:
npm run doctor -- --offline
```

`doctor` checks that:

- `deepseek-auth.json` / `DEEPSEEK_AUTH_DIR` exists;
- the JSON is valid;
- `token`, `cookie`, and `wasmUrl` are present;
- file permissions are safe on macOS/Linux (`0600`);
- the DeepSeek PoW endpoint is reachable (unless `--offline`).

If you see `data.biz_data is null`, `fetch failed`, `401/403/429`, or clients can't see models — run `npm run doctor` first.

---

## 🧪 Tests

Syntax checks plus unit tests:

```bash
npm test
```

Live smoke tests against a running proxy:

```bash
BASE_URL=http://127.0.0.1:9655 MODEL=deepseek-chat npm run test:live
```

---

## 📖 Docs

- [API Documentation](docs/api-documentation.md) — architecture, reverse-engineered DeepSeek Web endpoints, request/response formats, sessions, tool calling, error codes.
- [AGENTS.md](AGENTS.md) — orientation for AI agents working in this repo.

---

## 🔐 Security Notes

- `deepseek-auth.json`, `deepseek-auth-*.json`, `.env`, and Chrome profiles are gitignored — never commit them.
- Rotate your DeepSeek login with `npm run auth` when the proxy returns `401`/`403` or asks for a fresh PoW.
- If `PROXY_API_KEY` is unset, any bearer token is accepted; set a strong key before exposing the server beyond loopback.

---

## 📌 Project Status

FreeDeepseekAPI is an experimental web-chat proxy for local use and integrations. It depends on the current DeepSeek Web Chat contract, so upstream changes may require updates to the auth/session logic or model mapping.

If something stops working:

1. refresh the login via `npm run auth`;
2. check `/v1/model-capabilities`;
3. retry on a fresh session;
4. if the issue persists, DeepSeek likely changed its internal Web API.

---

## 👤 About the Author

Built and maintained by **[Ramadan Qaderizadeh](https://github.com/qaderizadeh)**.

This project showcases:

- **Reverse engineering** — DeepSeek's internal Web API, PoW challenge protocol, and SHA3 WASM solver
- **Protocol shims** — OpenAI Chat Completions, Anthropic Messages, and OpenAI Responses compatibility layers
- **LLM agent engineering** — prompt-emulated tool calling with robust multi-format parsing, plus reliability guards for long agentic sessions (narration fallback, loop breaker, tool-failure recovery)
- **Resilient async Node.js** — streaming SSE, session pooling, multi-account failover, rate-limit handling with backoff
- **Containerization** — hardened rootless Podman image with secrets and minimal privileges
- **Browser automation** — Chrome CDP auth flows, Playwright screenshot tooling

<p align="center">
  <strong>Ramadan Qaderizadeh</strong> · <a href="https://github.com/qaderizadeh">GitHub</a>
</p>
