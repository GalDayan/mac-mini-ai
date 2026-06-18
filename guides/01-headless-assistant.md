# 01 — Headless Mac mini as a Remote AI Assistant

> **Purpose.** Turn a fresh (or existing) **Apple Silicon Mac mini** into a *headless, always-on, remotely-controllable* assistant — a box you can reach from any other computer over [Tailscale](https://tailscale.com), with no keyboard, mouse, or monitor attached.

> 📖 **Conventions.** This guide follows the shared [agent conventions](../shared/conventions.md): the **Goal / Why / Run / Verify / If it fails / Idempotent** step-block format, the placeholder tokens, the **privilege model** for `sudo`, and the **golden safety rule** (never change remote access without a working fallback). Read that file first.

**Placeholders used here:** `<ADMIN_USER>`, `<MINI_HOSTNAME>`, `<LAN_IP>`, `<TS_IP>` — see the [conventions placeholder table](../shared/conventions.md#2-placeholders).

---

## What you end up with

After completing this guide, on every boot the mini will — with **no keyboard and no human at the machine**:

1. Power on automatically after a power outage.
2. Stay awake and reachable (no deep sleep).
3. Bring up **Tailscale at the login window**, *before anyone logs in*.
4. Accept a **Screen Sharing** connection to the login window, so you can type the password remotely from another machine.
5. Also be reachable over the **local network** (SSH + Screen Sharing) as a fallback.
6. Run your assistant runtime (e.g. Claude Code) on demand or persistently.

The result is a machine you treat like a small private server you can fully drive from your laptop.

---

## Assumptions & prerequisites

- Apple Silicon Mac mini (`uname -m` → `arm64`), macOS 13 Ventura or newer.
- An **admin** macOS account exists and you are logged into it once at the console for initial setup.
- A **Tailscale account** (the same tailnet your other devices use).
- A second computer (your laptop) on the **same local network** for first-time setup and as the fallback path.
- Internet access on the mini.

> **One-time keyboard.** You need a keyboard/monitor (or an existing remote session) **once**, for the initial setup. After this guide, you won't need them again.

---

## Phase A — LAN access foundation (the fallback, do this FIRST)

This makes the mini reachable over your local network independent of Tailscale, so later steps can't lock you out.

> ### Step A.1 — Name the machine
> - **Goal** — give the mini a stable, recognizable hostname.
> - **Why** — so it shows up clearly on your network and tailnet.
> - **Run**
>   ```bash
>   sudo scutil --set ComputerName "<MINI_HOSTNAME>"
>   sudo scutil --set HostName "<MINI_HOSTNAME>"
>   sudo scutil --set LocalHostName "<MINI_HOSTNAME>"
>   ```
> - **Verify** — `scutil --get HostName` → prints `<MINI_HOSTNAME>`.
> - **Idempotent** — yes.

> ### Step A.2 — Enable Remote Login (SSH over LAN)
> - **Goal** — get a terminal into the mini from your laptop over the local network.
> - **Why** — a text lifeline that does not depend on Tailscale or the GUI.
> - **Run**
>   ```bash
>   sudo systemsetup -setremotelogin on
>   ```
> - **Verify**
>   ```bash
>   sudo systemsetup -getremotelogin   # → Remote Login: On
>   lsof -nP -iTCP:22 -sTCP:LISTEN     # → sshd listening on 22
>   ```
> - **If it fails** — on newer macOS you may need to grant Full Disk Access to `sshd-keygen-wrapper`, or enable via System Settings → General → Sharing → Remote Login.
> - **Idempotent** — yes.

> ### Step A.3 — Enable Screen Sharing (GUI over LAN)
> - **Goal** — see and control the mini's screen, including the **login window**.
> - **Why** — this is how you type the password remotely after a reboot.
> - **Run**
>   ```bash
>   sudo launchctl enable system/com.apple.screensharing
>   sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null
>   ```
>   *(Equivalent GUI: System Settings → General → Sharing → Screen Sharing = On.)*
> - **Verify**
>   ```bash
>   lsof -nP -iTCP:5900 -sTCP:LISTEN   # → something listening on 5900
>   ```
> - **Idempotent** — yes.

> ### Step A.4 — Discover the LAN IP and TEST the fallback
> - **Goal** — confirm you can reach the mini over LAN before going further.
> - **Run**
>   ```bash
>   ipconfig getifaddr en0    # → this is <LAN_IP>, e.g. 172.16.101.6
>   ```
> - **Verify** — from your **laptop** on the same network:
>   - `ssh <ADMIN_USER>@<LAN_IP>` connects, **and**
>   - **Screen Sharing.app → Connect to `<LAN_IP>`** shows the desktop/login window.
> - **🛟 Do not proceed past this point until this fallback works** (golden safety rule).

---

## Phase B — Always-on power behavior

An assistant must survive power blips and never fall into unreachable deep sleep.

> ### Step B.1 — Auto-restart after power loss + no deep sleep
> - **Goal** — mini powers back on after an outage and stays reachable.
> - **Why** — headless boxes should recover unattended; sleep can drop the network.
> - **Run**
>   ```bash
>   sudo pmset -a autorestart 1      # restart automatically after a power failure
>   sudo pmset -a sleep 0            # never sleep the whole system
>   sudo pmset -a disksleep 0        # keep disks spun up
>   sudo pmset -a womp 1             # wake on network access
>   sudo pmset -a displaysleep 10    # screen can sleep; system stays awake
>   ```
> - **Verify** — `pmset -g | egrep 'autorestart|sleep|womp'` shows `autorestart 1`, `sleep 0`.
> - **Idempotent** — yes.

---

## Phase C — FileVault decision

> ### Step C.1 — Choose your disk-encryption posture
> - **Goal** — make a deliberate choice; it affects unattended boot.
> - **Why** — **FileVault on** = disk encrypted, but the mini **cannot finish booting after a power loss until someone unlocks it at the console** — which breaks unattended/headless recovery. **FileVault off** = the mini boots straight to the login window unattended (what we want for a headless assistant), at the cost of at-rest disk encryption.
> - **Decision**
>   - Headless assistant in a **physically trusted** location → **FileVault OFF** is the pragmatic choice (enables unattended boot).
>   - Sensitive data / untrusted location → keep **FileVault ON**, and accept that a power loss requires a one-time manual unlock.
> - **Run (to disable, only if you chose OFF)**
>   ```bash
>   sudo fdesetup status                 # check current state
>   sudo fdesetup disable                # prompts for a password; then it decrypts in the background
>   ```
> - **Verify** — `fdesetup status` → `FileVault is Off.` (decryption may take a while to finish).
> - **Idempotent** — yes (checks state first).

---

## Phase D — Tailscale that comes up BEFORE login

This is the core of remote-from-anywhere access. **Key fact:** the standard **Tailscale GUI app (the "macsys"/App Store variant) is a per-user app and cannot run before login** — it only connects after you log in. To reach the mini at the *login window*, run the open-source **`tailscaled` daemon as a system service** instead. The two must not run at the same time.

> ### Step D.1 — Install the tailscaled daemon (Homebrew)
> - **Goal** — get a system-level `tailscaled` that can run at boot.
> - **Run**
>   ```bash
>   # Install Homebrew if missing (Apple Silicon installs to /opt/homebrew)
>   command -v brew >/dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
>   eval "$(/opt/homebrew/bin/brew shellenv)"
>   brew install tailscale
>   ```
> - **Verify** — `/opt/homebrew/bin/tailscaled --version` prints a version.
> - **Idempotent** — yes.

> ### Step D.2 — Disable the GUI Tailscale app (avoid conflict)
> - **Goal** — ensure only the daemon manages the tunnel.
> - **Why** — running the GUI app and the daemon together fights over the network tunnel.
> - **Run** *(safe no-ops if the app isn't installed)*
>   ```bash
>   osascript -e 'quit app "Tailscale"' 2>/dev/null || true
>   osascript -e 'tell application "System Events" to delete login item "Tailscale"' 2>/dev/null || true
>   ```
> - **Verify** — `pgrep -lf Tailscale.app` returns nothing; Tailscale is absent from System Settings → Login Items.
> - **Note** — the dormant network **system extension** can stay; it does nothing while the app isn't running.
> - **Idempotent** — yes.

> ### Step D.3 — Run tailscaled at boot and authenticate
> - **Goal** — daemon starts at boot (before login) and joins your tailnet.
> - **Run**
>   ```bash
>   sudo brew services start tailscale          # installs a LaunchDaemon → starts at boot, before login
>   sudo /opt/homebrew/bin/tailscale up --ssh --hostname <MINI_HOSTNAME>
>   # ↑ MANUAL: prints a login URL. Open it in Safari ON THE MINI and approve.
>   #   --ssh also gives you a Tailscale-level terminal fallback.
>   ```
> - **Verify**
>   ```bash
>   sudo /opt/homebrew/bin/tailscale status     # mini shown as connected; note its <TS_IP>
>   sudo /opt/homebrew/bin/tailscale ip -4       # → <TS_IP>, e.g. 100.114.17.99
>   ```
> - **If it fails** — `sudo brew services list` should show `tailscale` as `started`. Re-run `tailscale up` to re-auth.
> - **Cleanup** — the new node may appear as `<MINI_HOSTNAME>-1` in the [admin console](https://login.tailscale.com/admin/machines); delete any stale duplicate of the old GUI node.
> - **Idempotent** — `brew services start` is yes; `tailscale up` re-auths harmlessly.

---

## Phase E — Install the assistant runtime

> ### Step E.1 — Developer baseline
> - **Goal** — tools the assistant needs to work.
> - **Run**
>   ```bash
>   xcode-select --install 2>/dev/null || true     # command line tools (git, etc.)
>   brew install git node                            # adjust to your stack
>   ```
> - **Verify** — `git --version`, `node --version` print versions.
> - **Idempotent** — yes.

> ### Step E.2 — Install Claude Code (the assistant)
> - **Goal** — install the agent you will drive remotely.
> - **Run**
>   ```bash
>   curl -fsSL https://claude.ai/install.sh | bash
>   # MANUAL: authenticate interactively once:
>   claude        # follow the login prompt, then /exit
>   ```
> - **Verify** — `claude --version` prints a version; a test prompt responds.
> - **Idempotent** — yes (re-running updates).

> ### Step E.3 (optional) — Keep the assistant running across reboots
> - **Goal** — have a long-lived assistant process start at login automatically.
> - **Why** — so background jobs survive reboots without manual restart.
> - **How** — create a per-user **LaunchAgent** at `~/Library/LaunchAgents/com.<ADMIN_USER>.assistant.plist` that launches your runtime, then:
>   ```bash
>   launchctl load -w ~/Library/LaunchAgents/com.<ADMIN_USER>.assistant.plist
>   ```
> - **Note** — a LaunchAgent runs **after** login. If you need work before login, drive it over SSH/Screen Sharing instead.
> - **Idempotent** — yes (`-w` is sticky).

---

## Phase F — Acceptance test (the real "plug-and-play" proof) ✅

> ### Step F.1 — Reboot and connect with nothing attached
> - **Goal** — prove the headless round-trip works end to end.
> - **Run**
>   ```bash
>   sudo reboot
>   ```
> - **Verify** (from your **laptop**, ideally with the mini's keyboard/monitor unplugged):
>   1. Wait ~60 seconds.
>   2. **Screen Sharing.app → Connect to `<TS_IP>`** (the Tailscale IP). You should reach the **login window**.
>   3. Type your macOS password remotely → desktop loads.
>   4. Confirm `ssh <ADMIN_USER>@<TS_IP>` also works.
> - **If Tailscale doesn't appear** — connect to `<LAN_IP>` (LAN fallback), then check `sudo /opt/homebrew/bin/tailscale status` and `sudo brew services list`.

If all four checks pass, the mini is a finished plug-and-play assistant. 🎉

---

## Quick verification cheatsheet

```bash
scutil --get HostName                              # hostname
sudo systemsetup -getremotelogin                   # SSH on?
lsof -nP -iTCP:5900 -sTCP:LISTEN                    # Screen Sharing on?
pmset -g | egrep 'autorestart|sleep|womp'          # power behavior
fdesetup status                                    # FileVault state
sudo brew services list | grep tailscale           # daemon running?
sudo /opt/homebrew/bin/tailscale status            # tailnet connectivity
```

---

## Rollback / uninstall

```bash
# Stop and remove the tailscaled daemon
sudo brew services stop tailscale
sudo /opt/homebrew/bin/tailscale logout
brew uninstall tailscale
# (Optional) go back to the GUI app: reinstall it and re-add to Login Items.

# Turn remote access back off
sudo systemsetup -setremotelogin off
sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null

# Restore default power behavior
sudo pmset -a sleep 1 disksleep 10 autorestart 0
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `sudo: a terminal is required to read the password` | Agent has no TTY | Operator runs the block interactively, or pre-cache with `sudo -v` |
| Can't reach `<TS_IP>` after reboot, but `<LAN_IP>` works | tailscaled didn't start / not authed | `sudo brew services restart tailscale`; re-run `tailscale up` |
| Tailscale connects only after you log in | The **GUI app** is still running | Revisit Step D.2; ensure only the daemon runs |
| Mini unreachable after a power outage | FileVault on, or `autorestart` off | Revisit Steps B.1 and C.1 |
| Screen Sharing shows black screen at login | Display asleep | Connect anyway; the session wakes it. Or set `displaysleep 0` |
| Two `mini` entries in Tailscale admin | Old GUI node + new daemon node | Delete the stale one in the admin console |
