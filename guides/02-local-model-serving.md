# 02 — Local model serving on a Mac mini

> **Purpose.** Run an **open-weight LLM locally** on an Apple Silicon Mac mini and expose it as an **OpenAI-compatible API** over your tailnet — so any device on your Tailscale network can use a private model with no cloud, no per-token cost, and no data leaving your hardware.

> 📖 **Conventions.** This guide follows the shared [agent conventions](../shared/conventions.md): the **Goal / Why / Run / Verify / If it fails / Idempotent** step-block format, the placeholder tokens, the **privilege model** for `sudo`, and the **golden safety rule**. Read that file first.

**Placeholders used here:** `<ADMIN_USER>`, `<MINI_HOSTNAME>`, `<LAN_IP>`, `<TS_IP>` (see the [conventions table](../shared/conventions.md#2-placeholders)), plus:

| Token | Meaning | Example |
|---|---|---|
| `<MODEL_REPO>` | HuggingFace MLX model id to serve | `mlx-community/Qwen3.6-35B-A3B-4bit` |
| `<SERVE_PORT>` | TCP port the model API listens on | `8080` |

> **Builds on guide 01.** This guide assumes the mini is already a reachable headless box (SSH + Screen Sharing + Tailscale) per [guide 01](01-headless-assistant.md). If it isn't, do that first — you'll want the tailnet to reach the model API.

---

## What you end up with

- A local LLM running on the mini via **MLX** (Apple's array framework — fastest path on Apple Silicon).
- An **OpenAI-compatible HTTP endpoint** (`/v1/chat/completions`) served by `mlx_lm.server`.
- That endpoint reachable **only over your tailnet** (not the public internet), as a **LaunchAgent** that restarts on boot.
- A repeatable way to **pick the right model for your RAM** and **measure real tokens/sec**.

---

## Assumptions & prerequisites

- Apple Silicon Mac mini (`uname -m` → `arm64`), macOS 13+; **16 GB RAM minimum**, 48 GB+ recommended for 30B-class models.
- Homebrew at `/opt/homebrew` (guide 01 installs it).
- Reachable over the tailnet as `<TS_IP>` (guide 01).
- Internet access for the one-time model download.

---

## Phase A — Pick a model that fits your RAM

The single most important decision. On Apple Silicon the GPU shares system RAM ("unified memory"), so **model size + context must fit in RAM** alongside macOS. Token-generation speed is bounded by **memory bandwidth ÷ active model size**, which is why **Mixture-of-Experts (MoE)** models — which activate only a few billion parameters per token — are the sweet spot on a mini.

> ### Step A.1 — Measure your usable memory
> - **Goal** — know your RAM budget before downloading anything.
> - **Why** — a model that doesn't fit will swap to disk and crawl (or get killed).
> - **Run**
>   ```bash
>   echo "$(($(sysctl -n hw.memsize)/1024/1024/1024)) GB total RAM"
>   sysctl -n machdep.cpu.brand_string        # e.g. Apple M4 Pro
>   ```
> - **Verify** — prints total RAM (e.g. `48 GB`) and the chip.
> - **Idempotent** — yes (read-only).

> ### Step A.2 — Choose a model for your tier
> - **Goal** — pick a 4-bit model that leaves ~30% RAM headroom for macOS + context.
> - **Rule of thumb** — a 4-bit model uses roughly **0.55 GB per billion parameters**. Keep model + KV-cache under ~70% of RAM.
>
> | RAM | Recommended default (quality + speed) | ~Disk/RAM | Lighter / faster option |
> |---|---|---|---|
> | 16 GB | `mlx-community/Qwen3-8B-4bit` | ~5 GB | `Qwen3-4B-4bit` |
> | 24–32 GB | `mlx-community/Qwen3.6-27B-4bit` | ~16 GB | `Qwen3-14B-4bit` |
> | **48 GB** | **`mlx-community/Qwen3.6-35B-A3B-4bit`** (MoE) | **~20 GB** | `Qwen3.6-27B-4bit` |
> | 64 GB+ | `Qwen3.6-35B-A3B-6bit` or `-8bit` | ~28 / 37 GB | `Qwen3.6-35B-A3B-4bit` |
>
> - **Why the 48 GB pick** — `Qwen3.6-35B-A3B` is a MoE with only ~3 B active params per token: it runs at the speed of a small model but answers at ~30 B-class quality, and at 4-bit (~20 GB) leaves ~28 GB for the OS and a large context window. For higher fidelity on 48 GB you can also run the **`4bit-DWQ`** variant (near-6-bit quality at 4-bit size).
> - **Idempotent** — yes (a decision, no system change).

---

## Phase B — Install the MLX runtime

MLX is Apple's framework; `mlx-lm` is the LLM toolkit on top of it. On Apple Silicon it is typically **10–30% faster than llama.cpp/Ollama** and uses less memory. We isolate it in a Python virtual environment so it never touches system Python.

> ### Step B.1 — Create an isolated Python environment for serving
> - **Goal** — a dedicated virtual environment holding a **recent** `mlx-lm` on a **recent** Python.
> - **Why** — keeps the server's deps off system Python, **and** new models need new code: a too-old `mlx-lm` fails with `Model type ... not supported` (e.g. Qwen3.6's `qwen3_5_moe` needs `mlx-lm ≥ 0.31`). We use [`uv`](https://github.com/astral-sh/uv), which ships its **own self-contained Python** — this sidesteps a real breakage seen on bleeding-edge macOS where the Homebrew `python@3.12` bottle has a broken `pyexpat` (`Symbol not found … libexpat`), and it avoids system Python being pinned to an old `mlx-lm`.
> - **Run**
>   ```bash
>   brew install uv
>   uv python install 3.12
>   uv venv --python 3.12 ~/mlx-serve
>   uv pip install --python ~/mlx-serve/bin/python mlx-lm     # needs mlx-lm ≥ 0.31 for Qwen3.6
>   ```
> - **Verify**
>   ```bash
>   ~/mlx-serve/bin/python -c "import mlx_lm, importlib.metadata as m; print('mlx-lm', m.version('mlx-lm'))"
>   ```
>   → prints `mlx-lm 0.31.x` (or newer).
> - **If it fails** — `Model type qwen3_5_moe not supported` ⇒ mlx-lm too old: `uv pip install --python ~/mlx-serve/bin/python -U mlx-lm`, or for a brand-new model install from git main (`uv pip install --python ~/mlx-serve/bin/python "mlx-lm @ git+https://github.com/ml-explore/mlx-lm"`). Also ensure `uname -m` is `arm64` (MLX is Apple-Silicon only) and macOS ≥ 13.5.
> - **Idempotent** — yes (venv create is one-time; install re-runs harmlessly).

> ### Step B.2 — Download and smoke-test the model
> - **Goal** — pull `<MODEL_REPO>` and confirm it generates, while measuring speed.
> - **Why** — proves the model fits and works before you wire up a service.
> - **Run** *(first run downloads ~20 GB to `~/.cache/huggingface`; subsequent runs are instant)*
>   ```bash
>   ~/mlx-serve/bin/python -m mlx_lm generate \
>     --model <MODEL_REPO> \
>     --prompt "In one paragraph, explain why MoE models are fast on Apple Silicon." \
>     --max-tokens 256
>   ```
> - **Verify** — prints a coherent paragraph, then a stats line:
>   `Generation: 256 tokens, NN.N tokens-per-sec` and `Peak memory: NN.N GB`.
>   On a 48 GB M4 Pro expect roughly **60–70 tok/s** and **~20 GB** peak (measured here: **66.9 tok/s**, **19.7 GB** — see [Benchmarks](#benchmarks--quality-of-the-recommended-model)).
> - **Note** — `Qwen3.6-35B-A3B` is a **reasoning model**: by default it emits a `<think>…</think>` trace before the final answer. That's expected; disable per-request with the API's `chat_template_kwargs` if you want answer-only output.
> - **If it fails** — `Peak memory` near your RAM total or an OOM kill ⇒ model too big; drop to a smaller tier in Step A.2.
> - **Idempotent** — yes (cached after first download).

---

## Phase C — Serve an OpenAI-compatible API (bound to the tailnet only)

> 🛟 **Safety rule applied here.** Do **not** bind the server to `0.0.0.0` (all interfaces) — that can expose an unauthenticated model to your whole LAN or the internet. Bind to the **Tailscale IP** so only tailnet devices reach it.

> ### Step C.1 — Confirm the tailnet IP to bind to
> - **Goal** — get the `<TS_IP>` the API will listen on.
> - **Run**
>   ```bash
>   /opt/homebrew/bin/tailscale ip -4      # → <TS_IP>, e.g. 100.114.17.99
>   ```
> - **Verify** — prints a `100.x.y.z` address.
> - **If it fails** — Tailscale isn't up; see [guide 01, Phase D](01-headless-assistant.md).
> - **Idempotent** — yes.

> ### Step C.2 — Launch the API server (foreground test)
> - **Goal** — serve `<MODEL_REPO>` on `<TS_IP>:<SERVE_PORT>` and confirm a request works.
> - **Why** — validate the endpoint before making it a boot service.
> - **Run** *(in one terminal)*
>   ```bash
>   ~/mlx-serve/bin/python -m mlx_lm server \
>     --model <MODEL_REPO> \
>     --host <TS_IP> --port <SERVE_PORT>
>   ```
> - **Verify** *(from another machine on the tailnet)*
>   ```bash
>   curl -s http://<TS_IP>:<SERVE_PORT>/v1/chat/completions \
>     -H "Content-Type: application/json" \
>     -d '{"messages":[{"role":"user","content":"Say hello in 5 words."}],"max_tokens":32}' \
>     | python3 -c "import sys,json;print(json.load(sys.stdin)['choices'][0]['message']['content'])"
>   ```
>   → prints a short reply. `Ctrl-C` to stop the foreground server.
> - **If it fails** — `curl: Connection refused` ⇒ check the host/port and that Tailscale is up on the client; a firewall prompt may need approval (see Step C.3).
> - **Idempotent** — yes (just a process; nothing persisted).

> ### Step C.3 — Allow the port through the macOS firewall (if enabled)
> - **Goal** — let tailnet traffic reach `<SERVE_PORT>`.
> - **Why** — the application firewall can silently block the Python process.
> - **Run**
>   ```bash
>   # Only needed if the application firewall is on. Allows the venv python.
>   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add ~/mlx-serve/bin/python
>   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp ~/mlx-serve/bin/python
>   ```
> - **Verify** — `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getappblocked ~/mlx-serve/bin/python` → not blocked.
> - **If it fails** — `MANUAL:` operator approves the GUI prompt "Do you want the application python to accept incoming connections?" → **Allow**.
> - **Idempotent** — yes (re-adding is harmless).

---

## Phase D — Keep the server running across reboots (LaunchAgent)

> ### Step D.1 — Install a per-user LaunchAgent
> - **Goal** — the model API starts automatically and restarts if it crashes.
> - **Why** — a serving box should come back on its own after a reboot.
> - **Run** *(writes the plist; substitute your tokens first)*
>   ```bash
>   PLIST=~/Library/LaunchAgents/ai.mac-mini.mlx-serve.plist
>   cat > "$PLIST" <<'EOF'
>   <?xml version="1.0" encoding="UTF-8"?>
>   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
>   <plist version="1.0"><dict>
>     <key>Label</key><string>ai.mac-mini.mlx-serve</string>
>     <key>ProgramArguments</key><array>
>       <string>/Users/<ADMIN_USER>/mlx-serve/bin/python</string>
>       <string>-m</string><string>mlx_lm</string><string>server</string>
>       <string>--model</string><string><MODEL_REPO></string>
>       <string>--host</string><string><TS_IP></string>
>       <string>--port</string><string><SERVE_PORT></string>
>     </array>
>     <key>RunAtLoad</key><true/>
>     <key>KeepAlive</key><true/>
>     <key>StandardOutPath</key><string>/tmp/mlx-serve.log</string>
>     <key>StandardErrorPath</key><string>/tmp/mlx-serve.err</string>
>   </dict></plist>
>   EOF
>   launchctl unload -w "$PLIST" 2>/dev/null || true
>   launchctl load -w "$PLIST"
>   ```
> - **Verify**
>   ```bash
>   launchctl list | grep mlx-serve            # shows the label with a PID
>   sleep 5 && curl -s http://<TS_IP>:<SERVE_PORT>/v1/models | head -c 200   # → JSON listing the model
>   ```
> - **If it fails** — read `/tmp/mlx-serve.err`. A `<TS_IP>` that changed (rare) means update the plist and reload.
> - **Idempotent** — yes (`-w` unload/load is safe to repeat).

---

## Phase E — Acceptance test ✅

> ### Step E.1 — Reboot and hit the API from another device
> - **Goal** — prove the serving box is plug-and-play.
> - **Run**
>   ```bash
>   sudo reboot
>   ```
> - **Verify** (from your **laptop** on the tailnet, after ~60 s):
>   ```bash
>   curl -s http://<TS_IP>:<SERVE_PORT>/v1/chat/completions \
>     -H "Content-Type: application/json" \
>     -d '{"messages":[{"role":"user","content":"What model are you?"}],"max_tokens":64}'
>   ```
>   → returns a JSON completion. The mini is now a private, always-on model server. 🎉
> - **If it fails** — connect to `<LAN_IP>` (fallback), check `launchctl list | grep mlx-serve` and `/tmp/mlx-serve.err`.

---

## Alternative runtimes

MLX is the recommended default on Apple Silicon, but two alternatives are worth knowing:

- **Ollama** — easiest to start (`brew install ollama && ollama serve`, then `ollama run qwen3`). Great DX, built-in model management, OpenAI-compatible API on `:11434`. Slightly slower than MLX and uses GGUF rather than MLX-optimized weights. Bind to the tailnet with `OLLAMA_HOST=<TS_IP>:11434`.
- **llama.cpp** (`brew install llama.cpp`, then `llama-server`) — most portable, widest model/quant support, good when MLX lags on a brand-new model. Comparable speed to Ollama.

Use **MLX for speed**, **Ollama for convenience**, **llama.cpp for breadth**.

---

## Benchmarks — quality of the recommended model

`Qwen3.6-35B-A3B` (the 48 GB default) reported scores, for context on what you're running locally:

| Benchmark | Score | What it measures |
|---|---|---|
| MMLU-Pro | 85.2 | broad knowledge + reasoning |
| AIME 2026 | 92.7 | competition math |
| SWE-bench Verified | 73.4 | real-world coding fixes |

**Measured on this mini** (M4 Pro, 48 GB, `mlx-lm` 0.31.3, 4-bit) — 256-token generation:

| Metric | Result |
|---|---|
| Generation speed | **66.9 tokens/sec** |
| Peak memory | **19.7 GB** (of 48 GB) |
| Model on disk | ~20 GB |

That's comfortably interactive (faster than reading speed) with ~28 GB of RAM still free for context and other apps.

---

## Rollback / uninstall

```bash
launchctl unload -w ~/Library/LaunchAgents/ai.mac-mini.mlx-serve.plist
rm ~/Library/LaunchAgents/ai.mac-mini.mlx-serve.plist
rm -rf ~/mlx-serve                                   # the venv
rm -rf ~/.cache/huggingface/hub/models--*            # downloaded weights (frees disk)
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Generation crawls / `Peak memory` near RAM total | Model too big for RAM | Smaller tier (Step A.2) or lower quant |
| `curl: Connection refused` from laptop | Bound to wrong host, or Tailscale down on client | Confirm `--host <TS_IP>`; check `tailscale status` both ends |
| Server unreachable after reboot | LaunchAgent not loaded / TS_IP changed | `launchctl list \| grep mlx-serve`; read `/tmp/mlx-serve.err`; update plist |
| Firewall prompt keeps blocking | App firewall on | Step C.3, or `MANUAL:` approve the GUI prompt |
| Model not found / download fails | Wrong repo id | Verify `<MODEL_REPO>` exists on huggingface.co |
| Want it faster | Using llama.cpp/Ollama | Switch to MLX 4-bit; close other GPU-heavy apps |
