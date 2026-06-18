#!/usr/bin/env bash
#
# bootstrap.sh — assisted provisioner for guide 01 (headless Mac mini assistant).
#
# Runs the SAFE, non-interactive steps automatically and prints "MANUAL:" markers
# wherever a human must act (auth prompts, browser logins, the reboot test).
# Follows shared/conventions.md. Targets Apple Silicon (/opt/homebrew).
#
# Usage:
#   MINI_HOSTNAME=mini-assistant bash scripts/bootstrap.sh
#
# Requires admin rights. Run in an interactive Terminal so sudo can prompt,
# or pre-cache credentials with `sudo -v` first.

set -euo pipefail

MINI_HOSTNAME="${MINI_HOSTNAME:-mini-assistant}"
BREW_PREFIX="/opt/homebrew"
TS="${BREW_PREFIX}/bin/tailscale"

say()    { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
manual() { printf '\n\033[1;33mMANUAL:\033[0m %s\n' "$*"; }
ok()     { printf '    \033[1;32m✓\033[0m %s\n' "$*"; }
die()    { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- preflight ---------------------------------------------------------------
[ "$(uname -m)" = "arm64" ] || die "This script targets Apple Silicon (arm64). See conventions.md for Intel paths."
say "Provisioning '${MINI_HOSTNAME}' as a headless Mac mini assistant"
sudo -v || die "Admin rights are required. Run in an interactive Terminal."

# --- Phase A: LAN fallback ---------------------------------------------------
say "Phase A — LAN access foundation (the fallback)"

sudo scutil --set ComputerName  "${MINI_HOSTNAME}"
sudo scutil --set HostName       "${MINI_HOSTNAME}"
sudo scutil --set LocalHostName  "${MINI_HOSTNAME}"
ok "hostname set to ${MINI_HOSTNAME}"

sudo systemsetup -setremotelogin on >/dev/null
ok "Remote Login (SSH) enabled"

sudo launchctl enable system/com.apple.screensharing 2>/dev/null || true
sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
ok "Screen Sharing enabled"

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || echo '')"
[ -n "$LAN_IP" ] && ok "LAN IP: ${LAN_IP}" || manual "Could not detect en0 IP; find the LAN IP manually."
manual "From your laptop on the same network, confirm BOTH work before continuing:"
manual "   ssh ${USER}@${LAN_IP:-<LAN_IP>}     and     Screen Sharing → ${LAN_IP:-<LAN_IP>}"

# --- Phase B: power behavior -------------------------------------------------
say "Phase B — Always-on power behavior"
sudo pmset -a autorestart 1
sudo pmset -a sleep 0
sudo pmset -a disksleep 0
sudo pmset -a womp 1
sudo pmset -a displaysleep 10
ok "auto-restart on, system sleep off, wake-on-network on"

# --- Phase C: FileVault (decision left to the operator) ----------------------
say "Phase C — FileVault decision"
FV_STATUS="$(fdesetup status 2>/dev/null || echo 'unknown')"
ok "current: ${FV_STATUS}"
manual "Decide disk encryption posture (see guide 01, Phase C):"
manual "   trusted location + unattended boot  -> 'sudo fdesetup disable'"
manual "   sensitive/untrusted                 -> keep FileVault ON (manual unlock after power loss)"

# --- Phase D: Tailscale daemon (before login) --------------------------------
say "Phase D — Tailscale daemon (reachable before login)"
if ! command -v brew >/dev/null 2>&1; then
  [ -x "${BREW_PREFIX}/bin/brew" ] || die "Homebrew not found. Install it, then re-run."
fi
eval "$(${BREW_PREFIX}/bin/brew shellenv)"
brew list tailscale >/dev/null 2>&1 || brew install tailscale
ok "tailscale/tailscaled installed"

# Disable the conflicting GUI app, if present.
osascript -e 'quit app "Tailscale"' 2>/dev/null || true
osascript -e 'tell application "System Events" to delete login item "Tailscale"' 2>/dev/null || true
ok "GUI Tailscale app quit + removed from Login Items (if it was present)"

sudo brew services start tailscale >/dev/null 2>&1 || sudo brew services restart tailscale >/dev/null 2>&1 || true
ok "tailscaled LaunchDaemon started (runs at boot, before login)"

manual "Authenticate the daemon — opens a browser login URL:"
manual "   sudo ${TS} up --ssh --hostname ${MINI_HOSTNAME}"
manual "Then verify:  sudo ${TS} status   and note the 100.x.y.z Tailscale IP."

# --- Phase E + F: handed to the operator -------------------------------------
say "Phase E — Assistant runtime"
manual "Install your runtime, e.g.:  brew install git node"
manual "Install Claude Code:          curl -fsSL https://claude.ai/install.sh | bash   (then 'claude' to log in)"

say "Phase F — Acceptance test"
manual "Reboot ('sudo reboot'), then from your laptop with NOTHING attached to the mini:"
manual "   Screen Sharing → <TS_IP>  should reach the LOGIN WINDOW; type your password remotely."
manual "   If Tailscale is missing, fall back to the LAN IP and check 'sudo brew services list'."

say "Automated steps complete. Finish the MANUAL items above to reach plug-and-play. 🎉"
