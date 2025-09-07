#!/bin/bash
#
# webapp-forge: create a native launcher for a website (clean-room rewrite)
#
# Features:
# - No gum dependency (plain read prompts; accepts CLI args)
# - Uses curl or wget (whichever is available)
# - Installs a tiny launcher to ~/.local/bin/webapp-run (Chromium-family app windows; Firefox fallback)
# - Per-app isolated profile dir; stable WMClass for window grouping
# - Stores icon under XDG data dir; writes a .desktop file
#

set -euo pipefail

# --------------------------- utilities ---------------------------
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

ask() {
  # ask VAR "Prompt" "default"
  local __var="$1" __prompt="$2" __default="${3-}" __ans
  read -rp "$__prompt${__default:+ [$__default]}: " __ans
  printf -v "$__var" '%s' "${__ans:-$__default}"
}

sanitize_id() {
  # lowercase + spaces->underscore; keep only [a-z0-9_.-] (ASCII collation)
  local s
  s=$(printf '%s' "$1" | LC_ALL=C tr '[:upper:] ' '[:lower:]_')
  LC_ALL=C tr -cd '[:alnum:]_.-' <<<"$s"
}

data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
apps_dir="$data_dir/applications"
icons_dir="$data_dir/icons/hicolor/256x256/apps"
bin_dir="$HOME/.local/bin"

mkdir -p "$apps_dir" "$icons_dir" "$bin_dir"

# ---------------------- one-time launcher install ----------------------
install_launcher() {
  local runner="$bin_dir/webapp-run"
  [[ -x "$runner" ]] && { echo "$runner"; return; }

  cat >"$runner" <<'RUNNER'
#!/bin/bash
set -euo pipefail

use_cmd() { command -v "$1" >/dev/null 2>&1; }

url=""
profile=""
wmclass=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile|--profile-dir|--user-data-dir) profile="$2"; shift 2 ;;
    --wmclass)  wmclass="$2"; shift 2 ;;
    --)         shift; break ;;
    -h|--help)  echo "usage: webapp-run [--profile DIR] [--wmclass CLASS] <URL> [extra browser flags]"; exit 0 ;;
    *)          url="$1"; shift; break ;;
  esac
done

extra=( "$@" )
[[ -n "$url" ]] || { echo "webapp-run: URL required" >&2; exit 1; }

# Prefer system default browser's .desktop if we can read it; fall back to known binaries.
desktop_id="$(xdg-settings get default-web-browser 2>/dev/null || true)"

candidate_bins=()
case "$desktop_id" in
  *chromium*.desktop|*chrome*.desktop|*brave*.desktop|*vivaldi*.desktop|*microsoft-edge*.desktop|*opera*.desktop|*thorium*.desktop)
    candidate_bins+=(chromium google-chrome brave vivaldi microsoft-edge opera thorium)
    ;;
  *firefox*.desktop|org.mozilla.firefox.desktop)
    candidate_bins+=(firefox)
    ;;
  *)
    candidate_bins+=(chromium google-chrome brave vivaldi microsoft-edge opera thorium firefox)
    ;;
esac
candidate_bins+=(xdg-open)

browser=""
for b in "${candidate_bins[@]}"; do
  if use_cmd "$b"; then browser="$b"; break; fi
done
[[ -n "$browser" ]] || { echo "webapp-run: no supported browser found" >&2; exit 1; }

supports_app=false
case "$browser" in
  *chromium*|*chrome*|*brave*|*vivaldi*|*microsoft-edge*|*opera*|*thorium*) supports_app=true ;;
esac

if $supports_app; then
  args=( "$browser" --app="$url" )
  [[ -n "$wmclass" ]] && args+=( --class="$wmclass" )
  [[ -n "$profile" ]] && args+=( --user-data-dir="$profile" )
  args+=( "${extra[@]}" )
else
  args=( "$browser" "$url" "${extra[@]}" )
fi

if use_cmd uwsm; then
  exec setsid uwsm app -- "${args[@]}"
elif use_cmd setsid; then
  exec setsid "${args[@]}"
else
  exec "${args[@]}"
fi
RUNNER
  chmod +x "$runner"
  echo "$runner"
}

# --------------------------- inputs ---------------------------
name="${1-}"
site="${2-}"
icon_url="${3-}"

if [[ $# -lt 3 ]]; then
  echo "Web App Forge — create a launcher"
  ask name     "App name"           "My Web App"
  ask site     "URL"                "https://example.org"
  ask icon_url "Icon URL (PNG)"     "https://example.org/icon.png"
fi

[[ -n "$name" && -n "$site" && -n "$icon_url" ]] || fail "name, URL, and icon URL are required"

# Safe identifier for filenames / WMClass
id="$(sanitize_id "$name")"
[[ -n "$id" ]] || fail "could not derive a safe ID from name"

desktop_path="$apps_dir/${id}.desktop"
icon_path="$icons_dir/${id}.png"
profile_dir="$data_dir/webapps/${id}"
wm_class="webapp-${id}"

mkdir -p "$profile_dir"

# --------------------------- download icon ---------------------------
if have curl; then
  curl -fsSL -o "$icon_path" "$icon_url" || fail "failed to download icon"
elif have wget; then
  wget -qO "$icon_path" "$icon_url" || fail "failed to download icon"
else
  fail "need curl or wget"
fi

# --------------------------- install runner ---------------------------
runner_path="$(install_launcher)"

# --------------------------- write desktop entry ---------------------------
cat >"$desktop_path" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Comment=$name
Exec=$runner_path --profile "$profile_dir" --wmclass "$wm_class" "$site"
Icon=$icon_path
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;Utility;
StartupWMClass=$wm_class
EOF

chmod 0644 "$desktop_path"

# Best-effort desktop/icon db refresh
have desktop-file-validate && desktop-file-validate "$desktop_path" >/dev/null 2>&1 || true
have update-desktop-database && update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
have gtk-update-icon-cache && gtk-update-icon-cache -q "$data_dir/icons" >/dev/null 2>&1 || true

printf 'Created launcher:\n  %s\nIcon:\n  %s\nRun from your app menu as: %s\n' "$desktop_path" "$icon_path" "$name"
