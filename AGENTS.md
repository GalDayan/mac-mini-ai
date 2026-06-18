# AGENTS.md

Instructions for any AI agent working in this repository — whether **executing** a playbook on a Mac or **authoring/editing** one. Read this first, then [`shared/conventions.md`](shared/conventions.md).

> This repo (`mac-mini-ai`) is a collection of playbooks for running AI on Apple Silicon Mac minis. Each guide is meant to be run **step-by-step by an AI agent** on the target machine, with a **human operator** approving privileged steps.

---

## Operating model

- **You (the agent)** execute commands, verify results, and report. You do *not* invent steps or skip verification.
- **The human operator** is available for anything you cannot do unattended: typing a `sudo` password, browser logins, GUI toggles, physical actions, and the reboot test.
- The target machine is often **headless** (no keyboard/monitor). A mistake that drops connectivity can require a physical trip. Treat connectivity as sacred.

---

## Prime directives

1. **Follow the conventions.** Every step uses the **Goal / Why / Run / Verify / If it fails / Idempotent** block defined in [`shared/conventions.md`](shared/conventions.md). A step is *done only when its Verify passes* — run the Verify command and confirm the expected output before continuing.
2. **Golden safety rule 🛟** — never reconfigure remote access (Tailscale, SSH, firewall, networking) without an **independent fallback already verified** (LAN SSH + Screen Sharing). If the fallback isn't confirmed working, stop and ask.
3. **Respect the privilege model.** You cannot type a `sudo` password. When a step needs admin or any human action, emit a clear **`MANUAL:`** instruction and hand it to the operator — do not guess or work around it.
4. **Prefer idempotent commands.** Gate any non-idempotent or destructive command behind a state check. Re-running a guide from the top should be safe.
5. **Replace placeholders, never hardcode real secrets.** Use the `<ANGLE_BRACKET>` tokens (`<ADMIN_USER>`, `<MINI_HOSTNAME>`, `<LAN_IP>`, `<TS_IP>`). This repo is **public** — no real credentials, private IPs you care about, or auth keys in committed files.
6. **Target Apple Silicon.** Tools live under `/opt/homebrew`. Use full paths for things that may not be on a minimal PATH (e.g. `/opt/homebrew/bin/tailscale`). Note Intel differences (`/usr/local`) only where relevant.

---

## When executing a guide

1. Read [`shared/conventions.md`](shared/conventions.md), then the target guide top to bottom before running anything.
2. Collect the placeholder values for this machine and substitute them.
3. Run phases **in order** — they are sequenced for safety (e.g. LAN fallback before Tailscale). Do not reorder.
4. After each step, run its **Verify** and report pass/fail. On failure, apply **If it fails** before proceeding; if still blocked, stop and report.
5. At each `MANUAL:` marker, pause and give the operator the exact command/action. Resume only after they confirm.
6. Finish with the guide's **Acceptance test** and report the result plainly.

## When authoring or editing a guide

1. One playbook per file in `guides/`, numbered (`NN-short-name.md`).
2. Use the standard step block; **every step needs a real Verify** with concrete expected output — never "should work."
3. Reference `shared/conventions.md` instead of repeating the format/placeholders/privilege/safety text.
4. Mark human-only steps with `MANUAL:`.
5. Sequence connectivity-affecting steps **after** their fallback is verified.
6. Update the **guide table in [`README.md`](README.md)** (and the roadmap if you complete a planned item).
7. If a helper script is involved, keep it runnable, `set -euo pipefail`, and print `MANUAL:` markers where a human must act (see [`scripts/bootstrap.sh`](scripts/bootstrap.sh)).

---

## Repo layout

```
mac-mini-ai/
├── AGENTS.md          # you are here — how agents work in this repo
├── README.md          # human-facing index + roadmap
├── guides/            # one numbered playbook per file
├── scripts/           # runnable helpers (bootstrap, etc.)
└── shared/            # conventions reused across all guides
```

## Commits

- Small, focused commits with a clear subject line; explain *why* in the body when non-obvious.
- Do not commit secrets, real auth keys, or machine-specific state.
- Branch off `main`; open a PR for review rather than force-pushing `main`.
