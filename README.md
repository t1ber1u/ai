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

```bash
curl https://qwen.yourdomain.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_LLAMA_API_KEY" \
  -d '{
    "messages": [
      {"role": "system", "content": "Raspunde scurt, natural, in romana."},
      {"role": "user",   "content": "Ce este inteligenta artificiala?"}
    ],
    "max_tokens": 80,
    "temperature": 0.2
  }'
```

For the **ephemeral** mode, replace the host with whatever
`*.trycloudflare.com` URL appears in the workflow logs (search the
"Start Cloudflare Tunnel" step output for `trycloudflare.com`).

---

## Constraints / non-goals

- CPU only — no GPU code paths.
- No Transformers / vLLM / SGLang. Just llama.cpp + GGUF.
- No full BF16 safetensors model.
- Model files are **never committed**.
- This is a hobby / feasibility setup. ~11 tok/s and a 6-hour
  GitHub-Actions window are real limits.
