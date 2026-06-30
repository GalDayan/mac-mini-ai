#!/usr/bin/env bash
#
# wifi-watchdog.sh — keep a headless Mac on its Wi-Fi and auto-recover silent drops.
#
# A headless Mac on Wi-Fi can lose its association and never rejoin on its own.
# Because Tailscale, SSH, and Screen Sharing all ride on top of the network, that
# means a total remote lockout until someone reconnects Wi-Fi at the machine.
#
# This script pings a known-reachable target; if it is unreachable it force
# power-cycles the Wi-Fi interface so macOS re-scans and rejoins the saved network
# (credentials come from the keychain — no password is stored here).
#
# Designed to run as a root LaunchDaemon every 60s (see guide 01, Step B.2), so it
# recovers before/without login. Safe to run by hand for testing.
#
# Config is read from the environment (the LaunchDaemon may set these), with
# sensible auto-detected defaults so it also works with no configuration.
set -uo pipefail

# Wi-Fi interface — auto-detected; override with WIFI_IFACE (e.g. en1).
IFACE="${WIFI_IFACE:-$( /usr/sbin/networksetup -listallhardwareports \
  | awk '/Hardware Port: Wi-Fi/{getline; print $2; exit}' )}"
IFACE="${IFACE:-en1}"

# Reachability probe. Prefer the LAN gateway (tests Wi-Fi association directly);
# when the link is down there is no default route, so fall back to a public anycast
# IP — which is also unreachable with Wi-Fi down, correctly triggering recovery.
PROBE="${PROBE_HOST:-$( /sbin/route -n get default 2>/dev/null | awk '/gateway/{print $2; exit}' )}"
PROBE="${PROBE:-1.1.1.1}"

# Optional: force-rejoin this SSID after the power-cycle (uses keychain creds).
# Leave empty to let macOS auto-join whatever saved network is in range.
SSID="${HOME_SSID:-}"

LOG="${WATCHDOG_LOG:-/var/log/wifi-watchdog.log}"

ts()     { date '+%Y-%m-%d %H:%M:%S'; }
logmsg() { echo "$(ts) $*" >> "$LOG" 2>/dev/null; }

# Healthy path — two quick pings, exit fast. This is the common case.
/sbin/ping -c 2 -t 3 "$PROBE" >/dev/null 2>&1 && exit 0
sleep 3
/sbin/ping -c 2 -t 3 "$PROBE" >/dev/null 2>&1 && exit 0   # ride out a momentary blip

logmsg "probe $PROBE unreachable — power-cycling $IFACE${SSID:+ to rejoin '$SSID'}"
/usr/sbin/networksetup -setairportpower "$IFACE" off; sleep 5
/usr/sbin/networksetup -setairportpower "$IFACE" on;  sleep 8
[ -n "$SSID" ] && /usr/sbin/networksetup -setairportnetwork "$IFACE" "$SSID" >/dev/null 2>&1
sleep 8

if /sbin/ping -c 2 -t 3 "$PROBE" >/dev/null 2>&1; then
  logmsg "recovery OK — $PROBE reachable again"
else
  logmsg "recovery attempted; $PROBE still unreachable — will retry next interval"
fi
exit 0
