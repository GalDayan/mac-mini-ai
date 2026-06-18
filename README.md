# mac-mini-ai

> Playbooks for running AI on **Apple Silicon Mac minis** — from a single headless assistant box you drive remotely, to local model serving, to clustering minis to host large LLMs.

Each playbook is written to be **executed step-by-step by an AI coding agent** (Claude Code or similar) running on the target machine, with a human operator approving privileged steps — and to be **read by a human** who wants to understand exactly what every step does and why.

---

## Guides

| # | Guide | What it does | Status |
|---|---|---|---|
| 01 | [Headless Mac mini as a Remote AI Assistant](guides/01-headless-assistant.md) | Turn a Mac mini into a headless, always-on box reachable from anywhere over Tailscale (before login), with a LAN fallback. | ✅ Ready |
| 02 | Local model serving | Run local LLMs on one mini (Ollama / MLX / llama.cpp), exposed over the tailnet. | 🚧 Planned |
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
│   └── 01-headless-assistant.md
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

## Roadmap

- [ ] **02 — Local model serving:** Ollama / MLX / llama.cpp on a single mini, model exposed over the tailnet, with benchmarks.
- [ ] **03 — Fleet:** sharding a large model across multiple minis; node discovery, health checks, and a single entrypoint.
- [ ] Shared `LaunchDaemon`/`LaunchAgent` templates for persistent services.
- [ ] MDM-friendly variants of each guide for managed fleets.

Contributions follow [the conventions](shared/conventions.md).
