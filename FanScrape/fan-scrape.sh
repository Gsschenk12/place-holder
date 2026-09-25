#!/bin/bash
# Light mechanical fan-scrape for macOS.
# Plays once about 8 seconds after you log in, and once at a random time
# during every hour the Mac stays awake.
#
# Install:  bash fan-scrape.sh
# Disable:  bash fan-scrape.sh --disable <key>
# A disable command without the key printed at install does nothing.

set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

LABEL="com.local.fanscrape"
SUPPORT="${HOME}/Library/Application Support/FanScrape"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
WAV="${SUPPORT}/scrape.wav"
KEY_FILE="${SUPPORT}/disable.key"
STAMP_FILE="${SUPPORT}/startup.stamp"
DAEMON="${SUPPORT}/fan-scrape.sh"
LOG_FILE="${SUPPORT}/play.log"
VOLUME="0.38"

random_offset() {
  /usr/bin/jot -r 1 120 3480
}

log_line() {
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" >> "${LOG_FILE}"
}

play_scrape() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if /usr/bin/afplay -v "${VOLUME}" "${WAV}"; then
      log_line "played"
      return 0
    fi
    sleep 3
  done
  log_line "play failed"
  return 1
}

ensure_key() {
  local raw key
  if [[ -f "${KEY_FILE}" ]]; then
    tr -d '[:space:]' < "${KEY_FILE}"
    return
  fi
  if raw="$(openssl rand -hex 8 2>/dev/null)" && [[ "${#raw}" -eq 16 ]]; then
    :
  else
    raw="$(uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]' | cut -c1-16)"
  fi
  key="${raw:0:4}-${raw:4:4}-${raw:8:4}-${raw:12:4}"
  printf '%s\n' "${key}" > "${KEY_FILE}"
  chmod 600 "${KEY_FILE}"
  printf '%s\n' "${key}"
}

write_plist() {
  cat > "${PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${DAEMON}</string>
    <string>--daemon</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>StandardOutPath</key>
  <string>${SUPPORT}/daemon.out</string>
  <key>StandardErrorPath</key>
  <string>${SUPPORT}/daemon.err</string>
</dict>
</plist>
EOF
}

cmd_disable() {
  local provided="${1:-}" stored
  if [[ -z "${provided}" ]]; then
    echo "Usage: bash fan-scrape.sh --disable <key>"
    echo "Nothing was removed."
    exit 1
  fi
  if [[ ! -f "${KEY_FILE}" ]]; then
    echo "No install was found. Nothing was removed."
    exit 1
  fi
  stored="$(tr -d '[:space:]' < "${KEY_FILE}")"
  if [[ "${provided}" != "${stored}" ]]; then
    echo "That key does not match. Nothing was removed."
    exit 1
  fi
  launchctl bootout "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
  rm -f "${PLIST}"
  rm -rf "${SUPPORT}"
  echo "Disabled. The fan scrape will not play again."
}

cmd_daemon() {
  local now last offset rest
  cd /
  now="$(date +%s)"
  last="0"
  if [[ -f "${STAMP_FILE}" ]]; then
    last="$(tr -d '[:space:]' < "${STAMP_FILE}")"
  fi
  [[ "${last}" =~ ^[0-9]+$ ]] || last="0"
  if (( now - last >= 90 )); then
    sleep 8
    play_scrape || true
    date +%s > "${STAMP_FILE}"
  fi
  while true; do
    offset="$(random_offset)"
    sleep "${offset}"
    play_scrape || true
    rest=$((3600 - offset))
    if (( rest > 0 )); then
      sleep "${rest}"
    fi
  done
}

cmd_install() {
  local source_dir source_wav key
  source_dir="$(cd "$(dirname "$0")" && pwd)"
  source_wav="${source_dir}/scrape.wav"
  if [[ ! -f "${source_wav}" ]]; then
    echo "Could not find scrape.wav next to this script." >&2
    exit 1
  fi
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Run this on the Mac." >&2
    exit 1
  fi

  mkdir -p "${SUPPORT}" "${HOME}/Library/LaunchAgents"
  chmod 700 "${SUPPORT}"
  if [[ "${source_wav}" != "${WAV}" ]]; then
    cp "${source_wav}" "${WAV}"
  fi
  if [[ "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")" != "${DAEMON}" ]]; then
    cp "$0" "${DAEMON}"
  fi
  chmod 700 "${DAEMON}"

  key="$(ensure_key)"
  date +%s > "${STAMP_FILE}"
  write_plist

  launchctl bootout "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
  launchctl enable "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
  if ! launchctl bootstrap "gui/$(id -u)" "${PLIST}"; then
    echo "The login item could not be loaded." >&2
    echo "Disable key: ${key}" >&2
    exit 1
  fi

  echo "Installed."
  echo "A short fan scrape plays about 8 seconds after you log in, and once at a random time during every hour the Mac stays awake."
  echo
  echo "Disable key: ${key}"
  echo "Disable with this command:"
  echo "bash \"${DAEMON}\" --disable ${key}"
  echo
  echo "That key is also saved in:"
  echo "${KEY_FILE}"
  echo
  echo "Playing it once now. Another scrape is scheduled at a random time in this hour."
  play_scrape || true
}

case "${1:-}" in
  --daemon) cmd_daemon ;;
  --disable) cmd_disable "${2:-}" ;;
  "") cmd_install ;;
  *)
    echo "Unknown option: ${1}" >&2
    echo "Install with: bash fan-scrape.sh" >&2
    echo "Disable with: bash fan-scrape.sh --disable <key>" >&2
    exit 1
    ;;
esac
