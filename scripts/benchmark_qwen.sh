#!/usr/bin/env bash
set -euo pipefail

MODEL_URL="${MODEL_URL:-}"
MODEL_FILE="${MODEL_FILE:-models/qwen3-4b-instruct-2507-q4.gguf}"
MAX_TOKENS="${MAX_TOKENS:-128}"
THREADS="${THREADS:-4}"
PROMPT="${PROMPT:-Raspunde scurt in romana: Ce este inteligenta artificiala?}"

if [[ -z "$MODEL_URL" ]]; then
  echo "ERROR: MODEL_URL is empty."
  echo "Provide a direct Hugging Face URL to a .gguf file, e.g.:"
  echo "  https://huggingface.co/<owner>/<repo>/resolve/main/<file>.gguf"
  exit 1
fi

echo "============================================================"
echo "System info"
echo "============================================================"
date
uname -a
echo "nproc: $(nproc)"
free -h || true
df -h || true
if command -v lscpu >/dev/null 2>&1; then
  lscpu
fi

echo "============================================================"
echo "Build llama.cpp"
echo "============================================================"
if [[ ! -d "llama.cpp" ]]; then
  git clone https://github.com/ggerganov/llama.cpp.git
fi

cmake -B llama.cpp/build -S llama.cpp -DCMAKE_BUILD_TYPE=Release
cmake --build llama.cpp/build --config Release -j2

echo "============================================================"
echo "Download model"
echo "============================================================"
mkdir -p models
echo "MODEL_URL=$MODEL_URL"
echo "MODEL_FILE=$MODEL_FILE"
curl -L --fail --retry 3 --retry-delay 5 -o "$MODEL_FILE" "$MODEL_URL"
ls -lh "$MODEL_FILE"

echo "============================================================"
echo "Locate llama binary"
echo "============================================================"
LLAMA_BIN=""
for candidate in \
  llama.cpp/build/bin/llama-cli \
  llama.cpp/build/bin/main; do
  if [[ -x "$candidate" ]]; then
    LLAMA_BIN="$candidate"
    break
  fi
done

if [[ -z "$LLAMA_BIN" ]]; then
  echo "ERROR: could not find llama-cli or main in llama.cpp/build/bin"
  ls -la llama.cpp/build/bin || true
  exit 1
fi
echo "Using LLAMA_BIN=$LLAMA_BIN"

echo "============================================================"
echo "Run inference"
echo "============================================================"
echo "PROMPT: $PROMPT"
echo "MAX_TOKENS: $MAX_TOKENS"
echo "THREADS: $THREADS"

set +e
"$LLAMA_BIN" \
  -m "$MODEL_FILE" \
  -p "$PROMPT" \
  -n "$MAX_TOKENS" \
  -t "$THREADS" \
  --temp 0.2 \
  --top-p 0.8 \
  --repeat-penalty 1.1 \
  2>&1 | tee benchmark-output.log
LLAMA_EXIT=${PIPESTATUS[0]}
set -e

echo "============================================================"
echo "llama.cpp timing lines"
echo "============================================================"
grep -iE "tokens per second|tok/s|eval time|prompt eval time|total time" benchmark-output.log || true

echo "============================================================"
echo "Final system info"
echo "============================================================"
df -h || true
free -h || true

if [[ "$LLAMA_EXIT" -ne 0 ]]; then
  echo "llama.cpp exited with code $LLAMA_EXIT"
  exit "$LLAMA_EXIT"
fi

echo "Done."
