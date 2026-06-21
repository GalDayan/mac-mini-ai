# mac-mini-ai

> Playbooks for running AI on **Apple Silicon Mac minis** — from a single headless assistant box you drive remotely, to local model serving, to clustering minis to host large LLMs.

Each playbook is written to be **executed step-by-step by an AI coding agent** (Claude Code or similar) running on the target machine, with a human operator approving privileged steps — and to be **read by a human** who wants to understand exactly what every step does and why.

---

## Guides

| # | Guide | What it does | Status |
|---|---|---|---|
| 01 | [Headless Mac mini as a Remote AI Assistant](guides/01-headless-assistant.md) | Turn a Mac mini into a headless, always-on box reachable from anywhere over Tailscale (before login), with a LAN fallback. | ✅ Ready |
| 02 | [Local model serving](guides/02-local-model-serving.md) | Run a local LLM on one mini via MLX (Ollama / llama.cpp alternatives), served as an OpenAI-compatible API over the tailnet. | ✅ Ready |
| 03 | Mac mini fleet for big models | Cluster multiple minis to host a model too large for one machine. | 🚧 Planned |

---

## How these guides work

All guides share one set of rules — read this first:

➡️ **[shared/conventions.md](shared/conventions.md)**

It defines:
- the **Goal / Why / Run / Verify / If it fails / Idempotent** step-block format,
- the **placeholder** tokens (`<ADMIN_USER>`, `<MINI_HOSTNAME>`, `<LAN_IP>`, `<TS_IP>`),
- the **privilege model** for `sudo` on a non-interactive agent,
- the **golden safety rule**: never change remote access without a working fallback.

---

## Repo layout

```
mac-mini-ai/
├── README.md                      # this index
├── guides/                        # one playbook per file, numbered
│   ├── 01-headless-assistant.md
│   └── 02-local-model-serving.md
├── scripts/                       # runnable helpers
│   └── bootstrap.sh               # non-interactive provisioner for guide 01
└── shared/                        # rules reused across guides
    └── conventions.md
```

---

## Quick start (guide 01)

```bash
# On the Mac mini, at the console, once:
git clone https://github.com/GalDayan/mac-mini-ai.git
cd mac-mini-ai
# Read guides/01-headless-assistant.md, or run the assisted bootstrap:
MINI_HOSTNAME=mini-assistant bash scripts/bootstrap.sh
```

The bootstrap runs the safe, non-interactive steps and **stops with `MANUAL:` markers** wherever a human must act (auth prompts, browser logins, reboot test).

---

## Quick start (guide 02 — local model serving)

```bash
# On the mini: install the MLX runtime in an isolated env (uv ships its own Python)
brew install uv
uv venv --python 3.12 ~/mlx-serve
uv pip install --python ~/mlx-serve/bin/python mlx-lm        # needs mlx-lm >= 0.31

# Run a model (downloads ~20 GB the first time, then cached). The CLI is the
# dotted command mlx_lm.generate — there is no bare `mlx_lm` command:
~/mlx-serve/bin/mlx_lm.generate \
  --model mlx-community/Qwen3.6-35B-A3B-4bit \
  --prompt "Hello!" --max-tokens 128

# Or serve an OpenAI-compatible API bound to the tailnet (not 0.0.0.0):
~/mlx-serve/bin/mlx_lm.server --model mlx-community/Qwen3.6-35B-A3B-4bit \
  --host "$(/opt/homebrew/bin/tailscale ip -4)" --port 8080
```

Measured on an M4 Pro / 48 GB: **~67 tok/s**, **~20 GB** peak. See [the full guide](guides/02-local-model-serving.md) for model sizing, firewall, a boot-time LaunchAgent, and the reboot acceptance test.

---

## Roadmap

- [x] **02 — Local model serving:** MLX (Ollama / llama.cpp alternatives) on a single mini, model exposed over the tailnet, with benchmarks. → [guide](guides/02-local-model-serving.md)
- [ ] **03 — Fleet:** sharding a large model across multiple minis; node discovery, health checks, and a single entrypoint.
- [ ] Shared `LaunchDaemon`/`LaunchAgent` templates for persistent services.
- [ ] MDM-friendly variants of each guide for managed fleets.

Contributions follow [the conventions](shared/conventions.md).
