# Qwen3-4B-Instruct-2507 GGUF Benchmark on GitHub Actions

This repository benchmarks **Qwen3-4B-Instruct-2507** on a standard GitHub
Actions Ubuntu runner.

## What it does

- Uses **llama.cpp** built from source.
- Loads a **GGUF quantized** version of Qwen3-4B-Instruct-2507.
- Runs **CPU-only** (the standard GitHub Actions runner has no GPU).
- Runs a single inference and **prints tokens/second** (and other timings)
  taken directly from llama.cpp's own output.
- Prints system info (CPU, memory, disk) for context.

This is **only a benchmark / feasibility test**, not a production serving
setup.

## How to run it

The workflow is triggered manually from the **Actions** tab using
**Run workflow** (`workflow_dispatch`).

You must provide a **direct Hugging Face URL** to a GGUF file.

### How to get a direct GGUF URL from Hugging Face

1. Open the original model page: `Qwen/Qwen3-4B-Instruct-2507`.
2. Click **Browse Quantizations** (or look in the community quantizations
   section).
3. Pick a GGUF repository (for example one published by `bartowski`,
   `unsloth`, `lmstudio-community`, etc.).
4. Open the **Files and versions** tab.
5. Find a `.gguf` file. **Recommended quantization: `Q4_K_M`** (or another
   `Q4` variant) — it is a good size/quality tradeoff on a CPU runner.
6. Right-click the file's download link and **Copy link address**, or
   construct the URL manually.

The URL must look like:

```
https://huggingface.co/<owner>/<repo>/resolve/main/<file>.gguf
```

> Use `resolve/main/...` (not `blob/main/...`) so `curl` gets the raw
> file.

## Workflow inputs

| Input        | Required | Default                                                                | Description                          |
|--------------|----------|------------------------------------------------------------------------|--------------------------------------|
| `model_url`  | yes      | —                                                                      | Direct URL to the `.gguf` file       |
| `max_tokens` | no       | `128`                                                                  | Tokens to generate                   |
| `prompt`     | no       | `Raspunde scurt in romana: Ce este inteligenta artificiala?`           | Prompt sent to the model             |

## Output

- The full llama.cpp run is captured into `benchmark-output.log` and
  uploaded as a workflow artifact.
- At the end of the run, the workflow greps and prints the timing /
  tokens-per-second lines from llama.cpp.

## Constraints / non-goals

- No GPU.
- No Transformers / vLLM / SGLang.
- No full BF16 safetensors model — GGUF quantized only.
- Model files are **never committed**; they are downloaded only during
  the workflow run.
