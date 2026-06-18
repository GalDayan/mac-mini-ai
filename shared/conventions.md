# Agent Conventions

> Shared rules for every playbook in this repo. Each guide references this file instead of repeating it, so all guides stay consistent and machine-actionable.
>
> **Audience.** Written for an **AI coding agent** executing steps in a Terminal on the target Mac, with a **human operator** available to approve privileged steps. Also written so a human can read along and understand each step.

---

## 1. Step block format

Every actionable step in a guide uses the same block, so it is unambiguous to execute and easy to skim:

> ### Step N.N — Short title
> - **Goal** — the single outcome this step achieves.
> - **Why** — plain-language reason (for the human).
> - **Run** — exact commands. `sudo` means admin rights are required.
> - **Verify** — a command whose output confirms success, with the expected result.
> - **If it fails** — the most common recovery.
> - **Idempotent** — `yes` means safe to re-run; `no` means check state first.

A step is only "done" when its **Verify** passes. Agents must run the Verify command and confirm the expected output before moving on.

---

## 2. Placeholders

Guides use `<ANGLE_BRACKET>` tokens for values that differ per machine. Replace them before running. Common tokens:

| Token | Meaning | Example |
|---|---|---|
| `<ADMIN_USER>` | The macOS admin account short name | `galdayan` |
| `<MINI_HOSTNAME>` | The name the Mac advertises on network/tailnet | `mini-assistant` |
| `<LAN_IP>` | The Mac's local network IP | `172.16.101.6` |
| `<TS_IP>` | The Mac's Tailscale IP | `100.114.17.99` |

Guides may define additional tokens locally; they will be listed at the top of that guide.

---

## 3. Privilege model (read before running `sudo`)

Many steps need `sudo`. A non-interactive agent **cannot type a password** — `sudo` fails with *"a terminal is required to read the password."* Handle this one of three ways:

1. **Operator runs privileged blocks** in an interactive Terminal (recommended) and pastes output back to the agent. In Claude Code, the human can prefix a command with `! ` to run it in-session.
2. **Pre-authorize the session:** the operator runs one `sudo -v` to cache credentials, then the agent runs `sudo` commands within the timeout window.
3. **(Advanced, audited)** Add a scoped `NOPASSWD` sudoers rule for the specific commands, then remove it when done.

When a guide reaches a step the agent cannot complete unattended (auth prompts, GUI approvals, browser logins), it marks it **`MANUAL:`** and hands it to the operator.

---

## 4. Golden safety rule 🛟

**Never reconfigure remote access without an independent fallback already working.**

On a headless Mac, establish **LAN-based** access (SSH + Screen Sharing over the local network) and confirm it works *before* touching anything that could interrupt connectivity (Tailscale, firewall, networking). One wrong step with no fallback = a physical trip to attach a keyboard.

---

## 5. Platform assumptions

- Commands target **Apple Silicon** Macs (`uname -m` → `arm64`). Homebrew lives at **`/opt/homebrew`**.
- On Intel Macs, Homebrew lives at `/usr/local`; adjust paths accordingly.
- macOS 13 Ventura or newer unless a guide states otherwise.

---

## 6. Design notes for agents authoring new guides

- Sequence destructive/connectivity-affecting steps **after** their fallback is verified.
- Prefer **idempotent** commands; gate non-idempotent ones behind a state check.
- Every step needs a **Verify** with concrete expected output — not "should work."
- Use `MANUAL:` for anything requiring a human (auth, GUI toggles, browser approval).
- Keep commands copy-pasteable: full paths for tools that may not be on a minimal PATH (e.g. `/opt/homebrew/bin/tailscale`).
