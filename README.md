# Qwen3-4B-Instruct-2507 on GitHub Actions

Two workflows live in this repo:

- **`benchmark-qwen.yml`** — one-shot CPU benchmark of llama.cpp + GGUF.
- **`qwen-public-api.yml`** — runs `llama-server` and exposes it as a
  public HTTPS API via **Cloudflare Tunnel**.

Both are **CPU-only**, **manually triggered** (`workflow_dispatch`),
and never commit the model file — it is downloaded at run time.

---

## Verified model URL

This GGUF has been tested and works end-to-end on the stock
`ubuntu-latest` runner:

```
https://huggingface.co/z8086486/Qwen3-4B-Instruct-2507-Q4_K_M-GGUF/resolve/main/qwen3-4b-instruct-2507-q4_k_m.gguf
```

- Quantization: **Q4_K_M**
- Size on disk: ~2.4 GB

---

## Verified benchmark result

Runner: `ubuntu-latest`, 4 vCPU AMD EPYC 7763, 15 GiB RAM, CPU-only.

| Stage                     | Cost                  |
|---------------------------|-----------------------|
| Model download            | ~35 s                 |
| Model load into RAM       | ~5–20 s               |
| Prompt eval               | **10.2 tok/s**        |
| Generation                | **11.0 tok/s**        |
| First short answer total  | ~45–60 s end-to-end   |
| Subsequent short answers  | ~3–6 s (model resident) |

**Verdict:** Qwen3-4B Q4_K_M is usable on free GitHub Actions for short
answers / batch inference. Not viable for interactive serving.

---

## Workflow 1 — `benchmark-qwen.yml` (one-shot benchmark)

Triggered manually from **Actions → Benchmark Qwen GGUF → Run workflow**.

Inputs:

| Input        | Required | Default                                                                | Description                          |
|--------------|----------|------------------------------------------------------------------------|--------------------------------------|
| `model_url`  | yes      | —                                                                      | Direct URL to a `.gguf` file         |
| `max_tokens` | no       | `128`                                                                  | Tokens to generate                   |
| `prompt`     | no       | `Raspunde scurt in romana: Ce este inteligenta artificiala?`           | Prompt sent to the model             |

The full llama.cpp run is captured to `benchmark-output.log` and uploaded
as a workflow artifact. The job greps and prints the timing /
tokens-per-second lines from llama.cpp at the end.

### How to get a direct GGUF URL from Hugging Face

1. Open `Qwen/Qwen3-4B-Instruct-2507`.
2. Click **Browse Quantizations**, pick a GGUF repo (e.g. one published
   by `bartowski`, `unsloth`, `lmstudio-community`, or the one above).
3. Open **Files and versions** in that repo.
4. Pick a `.gguf` file (recommended: **`Q4_K_M`**).
5. Right-click the download arrow → **Copy link address**.

URL shape: `https://huggingface.co/<owner>/<repo>/resolve/main/<file>.gguf`
(`resolve/main/...`, not `blob/main/...`).

---

## Workflow 2 — `qwen-public-api.yml` (public HTTPS LLM API)

Architecture:

```
GitHub Actions runner
  └─ llama-server on 127.0.0.1:8000  (OpenAI-compatible)
       └─ cloudflared tunnel
            └─ public HTTPS URL
                 └─ your external app / curl
```

Endpoint (OpenAI-compatible):
`POST <PUBLIC_URL>/v1/chat/completions`

### Triggers

- **Manual:** Actions → Qwen Public API → Run workflow.
- **Scheduled:** daily at **14:00 UTC** (= 17:00 Romania during EEST/DST).
- Job timeout: 6 hours (GitHub Actions hard cap). The tunnel keeps the
  job alive for that window.

### Tunnel modes (auto-selected)

The workflow looks for a `CLOUDFLARED_TUNNEL_TOKEN` repo secret:

| Secret present? | Mode | Public URL                                  |
|-----------------|------|---------------------------------------------|
| **No**          | Ephemeral (`trycloudflare.com`) | `https://random-words.trycloudflare.com` — changes every run |
| **Yes**         | Named tunnel                    | The public hostname you configured in Cloudflare (e.g. `https://qwen.yourdomain.com`) — stable |

### Optional API key

If you set the repo secret **`LLAMA_API_KEY`**, `llama-server` is
launched with `--api-key`, and callers must send:

```
Authorization: Bearer <your-key>
```

Without that secret, the endpoint is **unauthenticated** — anyone with
the URL can use it. Fine for quick tests, not for anything else.

---

## Cloudflare named-tunnel setup (one-time, ~5 minutes)

Skip this section if you are happy with the ephemeral `trycloudflare.com`
URL that changes on every run.

### Prereqs

- A Cloudflare account (free).
- A domain whose nameservers point to Cloudflare. (If your domain isn't
  on Cloudflare yet: dashboard → **+ Add a site** → follow the
  nameserver-change steps with your registrar. Free plan is enough.)

### Steps

1. Open **Cloudflare Zero Trust dashboard**:
   <https://one.dash.cloudflare.com>
2. **Networks → Tunnels → Create a tunnel**.
3. Connector type: **Cloudflared**. Click **Next**.
4. Name the tunnel (e.g. `qwen-api`). Click **Save tunnel**.
5. The next screen shows install commands for various OSes. You don't
   need to install anything locally — but **copy the token**. It's the
   long string that appears after `--token` in the example command
   (or just the value of the env var, depending on the OS tab). Treat
   it like a password.
6. Click **Next** → **Public Hostname** tab:
   - Subdomain: `qwen` (or whatever you like)
   - Domain: pick your Cloudflare-managed domain from the dropdown
   - Path: *(leave empty)*
   - Service: type `HTTP`, URL `localhost:8000`
   - **Save hostname**.
7. In GitHub, open this repo → **Settings → Secrets and variables →
   Actions → New repository secret**:
   - Name: `CLOUDFLARED_TUNNEL_TOKEN`
   - Value: paste the token from step 5.
   - **Add secret**.
8. (Optional, recommended) Add a second secret `LLAMA_API_KEY` with any
   random string. The workflow will require it as a Bearer token.
9. Trigger the workflow. Cloudflare will route
   `https://qwen.<yourdomain>/v1/...` to the runner.

### Test it

The currently deployed named tunnel in this repo is wired to:

- **Public hostname:** `qwen.price.com.ro`
- **Service:** `HTTP localhost:8000`
- **Tunnel:** `qwen-api` (in the `catalizatoare@gmail.com` Cloudflare account)

While the workflow is running, from any machine:

```bash
curl https://qwen.price.com.ro/v1/chat/completions \
  -H "Authorization: Bearer <LLAMA_API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "Raspunde scurt in romana: salut"}
    ],
    "max_tokens": 32,
    "temperature": 0.2
  }'
```

Replace `<LLAMA_API_KEY>` with the value you stored in the GitHub
`LLAMA_API_KEY` secret. Expected: a JSON response with
`choices[0].message.content` in ~3–6 s on a warm model.

For the **ephemeral** fallback (if `CLOUDFLARED_TUNNEL_TOKEN` is removed
from the repo secrets), replace the host with the `*.trycloudflare.com`
URL printed in the workflow's "Start Cloudflare Tunnel" step.

---

## How to run the public API workflow

1. **Actions → Qwen Public API → Run workflow** (or wait for the
   scheduled 14:00 UTC daily run).
2. Watch the logs. Key signals to confirm the run is healthy:
   - `Step: Start llama-server` → `LLAMA_API_KEY: SET` → `Server reports healthy after Ns.` → local `HTTP_STATUS=200` on both `/health` and `/v1/chat/completions`.
   - `Step: Start Cloudflare Tunnel` → `CLOUDFLARED_TUNNEL_TOKEN: SET` → `Tunnel mode: NAMED` → cloudflared lines like `Registered tunnel connection` × 4.
3. In Cloudflare Zero Trust → Networks → Tunnels, the `qwen-api`
   tunnel flips from **Inactive** to **Healthy**.
4. Call `https://qwen.price.com.ro/v1/chat/completions` from outside.

The job keeps running (and the tunnel keeps routing) until the 6h
GitHub-Actions timeout, until you cancel the run from the Actions UI,
or until cloudflared/llama-server errors out.

---

## Troubleshooting

| Symptom | Likely cause / where to look |
|---|---|
| Cloudflare tunnel stays **Inactive** while the workflow runs | `cloudflared` didn't connect. Check the "Start Cloudflare Tunnel" step output for auth errors. Most common: `CLOUDFLARED_TUNNEL_TOKEN` secret is missing, expired, or from a deleted tunnel. Recreate the tunnel in Cloudflare and update the secret. |
| Step header prints `Tunnel mode: EPHEMERAL` and a `trycloudflare.com` URL | `CLOUDFLARED_TUNNEL_TOKEN` is not detected. The secret is missing, named differently, or scoped to environment instead of repository. Re-check GitHub → Settings → Secrets and variables → Actions. |
| Tunnel is **Healthy** but `curl https://qwen.price.com.ro/...` returns 502 / 530 / 1033 | The public hostname → service mapping is wrong. In Cloudflare → Tunnels → `qwen-api` → **Published application routes**, confirm hostname `qwen.price.com.ro`, type **HTTP**, URL **`localhost:8000`**. |
| Workflow step `Start llama-server` exits with `ERROR: llama-server did not become healthy within 180s.` | llama-server crashed during boot. Check `llama-server.log` (also uploaded as artifact). Usually OOM, corrupt GGUF, or unsupported quant. |
| Local probe `POST /v1/chat/completions` returns `401` or `403` | API key mismatch. Either the workflow started without `LLAMA_API_KEY` (then *don't* send `Authorization`) or you're calling with a different key than what's stored in the secret. |
| External `curl` returns `401` | Caller didn't send `Authorization: Bearer <LLAMA_API_KEY>`, or sent the wrong key. The repo `LLAMA_API_KEY` secret value is what you must match. |
| External `curl` returns Cloudflare 1033 ("Argo Tunnel error") | No `cloudflared` connector is online. Workflow probably ended (job hit 6h or was cancelled). Re-run the workflow. |
| External `curl` returns 404 on the hostname | DNS for `qwen.price.com.ro` doesn't resolve to Cloudflare, or the hostname route was deleted. Confirm the route still exists in the tunnel. |
| Step takes >5 min on "Build llama.cpp" every run | Normal — no caching here. Could be added with `actions/cache` over `llama.cpp/build`, but the build is reliable and we haven't bothered. |

### Confirming `llama-server` API key support

The `--api-key` flag is supported by `llama-server` in current llama.cpp
builds (the workflow builds from `ggml-org/llama.cpp` `main`). When set,
the server returns `401 Unauthorized` to any request without
`Authorization: Bearer <key>`. No proxy needed — auth is handled by
llama-server itself.

---

## Constraints / non-goals

- CPU only — no GPU code paths.
- No Transformers / vLLM / SGLang. Just llama.cpp + GGUF.
- No full BF16 safetensors model.
- Model files are **never committed**.
- This is a hobby / feasibility setup. ~11 tok/s and a 6-hour
  GitHub-Actions window are real limits.
