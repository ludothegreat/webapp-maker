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
# - Configurable via config file
# - Full Wayland support (Sway, Hyprland, KDE Plasma, GNOME, and other wlroots-based compositors)
# - Automatic display server detection (Wayland/X11)
#

set -euo pipefail

# --------------------------- utilities ---------------------------
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
warn() { printf 'warning: %s\n' "$*" >&2; }
info() { [[ -z "${VERBOSE:-}" ]] || printf 'info: %s\n' "$*"; }
confirm() { 
  local prompt="$1"
  local a
  read -rp "$prompt [y/N]: " a
  [[ "${a,,}" == y || "${a,,}" == yes ]]
}

# --------------------------- TUI functions ---------------------------
USE_DIALOG=0
if have dialog; then
  USE_DIALOG=1
fi

# TUI input function (works with or without dialog)
tui_input() {
  local var="$1"
  local prompt="$2"
  local default="${3:-}"
  
  if [[ $USE_DIALOG -eq 1 ]]; then
    local result
    result=$(dialog --stdout --inputbox "$prompt" 0 0 "$default" 2>&1)
    [[ $? -eq 0 ]] && printf -v "$var" '%s' "$result" || return 1
  else
    ask "$var" "$prompt" "$default"
  fi
}

# TUI menu function
tui_menu() {
  local title="$1"
  shift
  local items=("$@")
  local choice
  
  if [[ $USE_DIALOG -eq 1 ]]; then
    local menu_items=()
    local i=0
    for item in "${items[@]}"; do
      menu_items+=("$i" "$item")
      ((i++))
    done
    choice=$(dialog --stdout --menu "$title" 0 0 0 "${menu_items[@]}" 2>&1)
    [[ $? -eq 0 ]] && echo "$choice" || return 1
  else
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$title"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local i=0
    for item in "${items[@]}"; do
      printf "  %d) %s\n" "$i" "$item"
      ((i++))
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    while true; do
      read -rp "Select option [0-$((i-1))]: " choice
      [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 0 && "$choice" -lt $i ]] && break
      echo "Invalid option. Please enter a number between 0 and $((i-1))."
    done
    echo "$choice"
  fi
}

# TUI message box
tui_msg() {
  local title="$1"
  local message="$2"
  
  if [[ $USE_DIALOG -eq 1 ]]; then
    dialog --msgbox "$message" 0 0
  else
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$title"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$message"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    read -rp "Press Enter to continue..."
  fi
}

# TUI yes/no dialog
tui_confirm() {
  local prompt="$1"
  
  if [[ $USE_DIALOG -eq 1 ]]; then
    dialog --yesno "$prompt" 0 0
    return $?
  else
    confirm "$prompt"
  fi
}

# Select webapp from list
tui_select_webapp() {
  local title="$1"
  local apps=()
  local app_ids=()
  
  shopt -s nullglob
  for f in "$apps_dir"/*.desktop; do
    [[ -f "$f" ]] || continue
    local exec_line="$(desktop_get Exec "$f")"
    if [[ -n "$exec_line" ]] && grep -qE 'webapp-run' <<<"$exec_line"; then
      local base="$(basename "${f%.*}")"
      local nm="$(desktop_get Name "$f")"
      apps+=("$nm (ID: $base)")
      app_ids+=("$base")
    fi
  done
  
  if [[ ${#apps[@]} -eq 0 ]]; then
    tui_msg "No Webapps" "No webapps found. Create one first!"
    return 1
  fi
  
  local choice
  choice=$(tui_menu "$title" "${apps[@]}")
  [[ -z "$choice" ]] && return 1
  
  echo "${app_ids[$choice]}"
}


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

# --------------------------- configuration ---------------------------
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/webapp-maker"
global_config="$config_dir/config.ini"
apps_config_dir="$config_dir/apps"

# Default configuration values
declare -A CONFIG
CONFIG[browser_command]=""
CONFIG[browser_detection_method]="auto"
CONFIG[browser_fallbacks]="chromium,firefox,google-chrome"
CONFIG[paths_desktop_dir]=""
CONFIG[paths_icon_dir]=""
CONFIG[paths_profile_dir]=""
CONFIG[paths_bin_dir]=""
CONFIG[app_icon_size]="256"
CONFIG[app_wmclass_prefix]="webapp-"
CONFIG[app_extra_flags]=""
CONFIG[browser_wayland_mode]="auto"

# Load INI config file
load_config_file() {
  local config_file="$1"
  [[ ! -f "$config_file" ]] && return 1
  
  # Validate file is readable
  [[ -r "$config_file" ]] || { warn "Config file not readable: $config_file"; return 1; }
  
  local current_section=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Remove comments and trim
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    
    # Section header
    if [[ "$line" =~ ^\[(.+)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      continue
    fi
    
    # Key=value
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      # Remove leading/trailing whitespace from key and value
      key="${key#"${key%%[![:space:]]*}"}"
      key="${key%"${key##*[![:space:]]}"}"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      
      if [[ -n "$current_section" ]]; then
        CONFIG["${current_section}_${key}"]="$value"
      else
        CONFIG["$key"]="$value"
      fi
    fi
  done < "$config_file"
  return 0
}

# Get config value with fallback chain: env var > per-app config > global config > default
get_config_value() {
  local key="$1"
  local env_key="WEBAPP_$(echo "$key" | tr '[:lower:]' '[:upper:]' | tr '_' '_')"
  
  # Check environment variable first
  if [[ -n "${!env_key:-}" ]]; then
    printf '%s' "${!env_key}"
    return 0
  fi
  
  # Check per-app config (if app_id is set)
  if [[ -n "${APP_CONFIG_LOADED:-}" && -n "${CONFIG["app_${key}"]:-}" ]]; then
    printf '%s' "${CONFIG["app_${key}"]}"
    return 0
  fi
  
  # Check global config
  if [[ -n "${CONFIG["$key"]:-}" ]]; then
    printf '%s' "${CONFIG["$key"]}"
    return 0
  fi
  
  return 1
}

# Load global config
load_config() {
  mkdir -p "$config_dir"
  
  # Load global config if it exists
  if [[ -f "$global_config" ]]; then
    load_config_file "$global_config" || true
  fi
}

# Load per-app config
load_app_config() {
  local app_id="$1"
  [[ -z "$app_id" ]] && return 1
  
  local app_config="$apps_config_dir/${app_id}.ini"
  if [[ -f "$app_config" ]]; then
    load_config_file "$app_config" || true
    APP_CONFIG_LOADED=1
    return 0
  fi
  return 1
}

# Initialize default config file if it doesn't exist
init_default_config() {
  [[ -f "$global_config" ]] && return 0
  
  mkdir -p "$config_dir" || fail "Failed to create config directory: $config_dir"
  
  if ! cat >"$global_config" <<'EOF'
[browser]
# Explicit browser command (e.g., "firefox", "chromium", "google-chrome")
# If empty, auto-detect from system default
command=

# Browser detection method: "xdg-settings", "desktop-file", "auto"
detection_method=auto

# Fallback browsers to try (comma-separated)
fallbacks=chromium,firefox,google-chrome

[paths]
# Desktop file directory (default: $XDG_DATA_HOME/applications)
desktop_dir=

# Icon directory (default: $XDG_DATA_HOME/icons/hicolor/256x256/apps)
icon_dir=

# Profile directory base (default: $XDG_DATA_HOME/webapps)
profile_dir=

# Binary/launcher directory (default: $HOME/.local/bin)
bin_dir=

[app]
# Default icon size (for future use)
icon_size=256

# WMClass prefix (default: "webapp-")
wmclass_prefix=webapp-

# Additional browser flags (space-separated)
extra_flags=

# Wayland mode: "auto" (detect), "force" (force Wayland), "x11" (force X11)
# Note: This is usually auto-detected, but can be overridden if needed
wayland_mode=auto
EOF
  then
    warn "Failed to create default config file: $global_config"
    return 1
  fi
}

# Initialize paths from config with defaults
init_paths() {
  data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
  
  # Get paths from config or use defaults
  local desktop_dir_config
  desktop_dir_config="$(get_config_value "paths_desktop_dir" 2>/dev/null || echo "")"
  apps_dir="${desktop_dir_config:-$data_dir/applications}"
  
  local icon_dir_config
  icon_dir_config="$(get_config_value "paths_icon_dir" 2>/dev/null || echo "")"
  icons_dir="${icon_dir_config:-$data_dir/icons/hicolor/256x256/apps}"
  
  local bin_dir_config
  bin_dir_config="$(get_config_value "paths_bin_dir" 2>/dev/null || echo "")"
  bin_dir="${bin_dir_config:-$HOME/.local/bin}"
  
  local profile_dir_config
  profile_dir_config="$(get_config_value "paths_profile_dir" 2>/dev/null || echo "")"
  profile_base_dir="${profile_dir_config:-$data_dir/webapps}"
  
  # Validate and create paths
  mkdir -p "$apps_dir" "$icons_dir" "$bin_dir" "$profile_base_dir" || fail "Failed to create directories"
  [[ -w "$apps_dir" ]] || fail "Desktop directory not writable: $apps_dir"
  [[ -w "$icons_dir" ]] || fail "Icon directory not writable: $icons_dir"
  [[ -w "$bin_dir" ]] || fail "Binary directory not writable: $bin_dir"
  
  # Validate paths are absolute or warn
  [[ "$apps_dir" == /* ]] || warn "Desktop directory should be absolute: $apps_dir"
  [[ "$icons_dir" == /* ]] || warn "Icon directory should be absolute: $icons_dir"
  [[ "$bin_dir" == /* ]] || warn "Binary directory should be absolute: $bin_dir"
}

# ---------------------- one-time launcher install ----------------------
install_launcher() {
  local runner="$bin_dir/webapp-run"
  local app_id_for_browser="${1:-}"  # Optional app ID for per-app browser override
  
  # Check if launcher needs update (if app_id provided and has per-app browser)
  local needs_update=0
  if [[ -n "$app_id_for_browser" ]]; then
    load_app_config "$app_id_for_browser"
    local app_browser="$(get_config_value "browser_command" 2>/dev/null || echo "")"
    if [[ -n "$app_browser" ]]; then
      needs_update=1
      info "Per-app browser override detected, updating launcher"
    fi
  fi
  
  # Only skip if launcher exists and doesn't need update
  if [[ -x "$runner" ]] && [[ $needs_update -eq 0 ]]; then
    echo "$runner"
    return
  fi
  
  # Get browser config for launcher
  local browser_cmd=""
  
  # Try per-app browser override first (if app_id provided)
  if [[ -n "$app_id_for_browser" ]] && [[ -n "${APP_CONFIG_LOADED:-}" ]]; then
    browser_cmd="$(get_config_value "browser_command" 2>/dev/null || echo "")"
    [[ -n "$browser_cmd" ]] && info "Using per-app browser: $browser_cmd"
  fi
  
  # Fall back to global config if no per-app override
  if [[ -z "$browser_cmd" ]]; then
    browser_cmd="$(get_config_value "browser_command" 2>/dev/null || echo "")"
  fi
  
  # Validate browser command if explicitly set
  if [[ -n "$browser_cmd" ]] && ! have "$browser_cmd"; then
    warn "Configured browser not found: $browser_cmd (will use auto-detection)"
    browser_cmd=""
  fi
  
  local detection_method
  detection_method="$(get_config_value "browser_detection_method" 2>/dev/null || echo "auto")"
  
  # Validate detection method
  case "$detection_method" in
    xdg-settings|desktop-file|auto) ;;
    *) warn "Invalid detection_method: $detection_method, using 'auto'"; detection_method="auto" ;;
  esac
  
  local fallbacks
  fallbacks="$(get_config_value "browser_fallbacks" 2>/dev/null || echo "chromium,firefox,google-chrome")"
  
  local wayland_mode
  wayland_mode="$(get_config_value "browser_wayland_mode" 2>/dev/null || echo "auto")"

  cat >"$runner" <<RUNNER
#!/bin/bash
set -euo pipefail

use_cmd() { command -v "\$1" >/dev/null 2>&1; }

# Config from installer
BROWSER_CMD="${browser_cmd}"
DETECTION_METHOD="${detection_method}"
FALLBACKS="${fallbacks}"
WAYLAND_MODE="${wayland_mode}"

url=""
profile=""
wmclass=""
browser_override=""

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --profile|--profile-dir|--user-data-dir) profile="\$2"; shift 2 ;;
    --wmclass)  wmclass="\$2"; shift 2 ;;
    --browser)  browser_override="\$2"; shift 2 ;;
    --)         shift; break ;;
    -h|--help)  echo "usage: webapp-run [--profile DIR] [--wmclass CLASS] [--browser CMD] <URL> [extra browser flags]"; exit 0 ;;
    *)          url="\$1"; shift; break ;;
  esac
done

extra=( "\$@" )
[[ -n "\$url" ]] || { echo "webapp-run: URL required" >&2; exit 1; }

# Parse desktop file to get browser command
parse_desktop_file() {
  local desktop_id="\$1"
  local desktop_file=""
  
  # Try XDG data dirs
  for dir in "\${XDG_DATA_HOME:-\$HOME/.local/share}/applications" \
             /usr/share/applications \
             /usr/local/share/applications; do
    if [[ -f "\$dir/\$desktop_id" ]]; then
      desktop_file="\$dir/\$desktop_id"
      break
    fi
    # Try without .desktop extension
    if [[ -f "\$dir/\${desktop_id%.desktop}.desktop" ]]; then
      desktop_file="\$dir/\${desktop_id%.desktop}.desktop"
      break
    fi
  done
  
  [[ -z "\$desktop_file" || ! -f "\$desktop_file" ]] && return 1
  
  # Extract Exec= line and get the first command
  local exec_line
  exec_line="\$(grep -i -m1 "^Exec=" "\$desktop_file" 2>/dev/null || true)"
  [[ -z "\$exec_line" ]] && return 1
  
  # Remove Exec= prefix and extract first word (handling %u, %U, %f, %F)
  exec_line="\${exec_line#Exec=}"
  exec_line="\${exec_line%% *}"
  exec_line="\${exec_line%%%*}"
  
  # If it's a full path, use it; otherwise try to find the command
  if [[ "\$exec_line" == /* ]]; then
    [[ -x "\$exec_line" ]] && echo "\$exec_line" && return 0
  else
    if use_cmd "\$exec_line"; then
      echo "\$exec_line"
      return 0
    fi
  fi
  return 1
}

# Enhanced browser detection
browser=""

# 1. Explicit override (command line)
if [[ -n "\$browser_override" ]]; then
  if use_cmd "\$browser_override"; then
    browser="\$browser_override"
  else
    echo "webapp-run: specified browser not found: \$browser_override" >&2
    exit 1
  fi
# 2. Config file browser command
elif [[ -n "\$BROWSER_CMD" ]]; then
  if use_cmd "\$BROWSER_CMD"; then
    browser="\$BROWSER_CMD"
  else
    echo "webapp-run: configured browser not found: \$BROWSER_CMD" >&2
  fi
fi

# 3. Auto-detection if not set
if [[ -z "\$browser" ]]; then
  case "\$DETECTION_METHOD" in
    xdg-settings)
      desktop_id="\$(xdg-settings get default-web-browser 2>/dev/null || true)"
      if [[ -n "\$desktop_id" ]]; then
        parsed="\$(parse_desktop_file "\$desktop_id" 2>/dev/null || true)"
        [[ -n "\$parsed" ]] && browser="\$parsed"
      fi
      ;;
    desktop-file)
      # Try to find default browser desktop file
      desktop_id="\$(xdg-settings get default-web-browser 2>/dev/null || true)"
      if [[ -n "\$desktop_id" ]]; then
        parsed="\$(parse_desktop_file "\$desktop_id" 2>/dev/null || true)"
        [[ -n "\$parsed" ]] && browser="\$parsed"
      fi
      # Also try xdg-mime
      if [[ -z "\$browser" ]]; then
        desktop_id="\$(xdg-mime query default x-scheme-handler/http 2>/dev/null || true)"
        if [[ -n "\$desktop_id" ]]; then
          parsed="\$(parse_desktop_file "\$desktop_id" 2>/dev/null || true)"
          [[ -n "\$parsed" ]] && browser="\$parsed"
        fi
      fi
      ;;
    auto|*)
      # Try xdg-settings first
      desktop_id="\$(xdg-settings get default-web-browser 2>/dev/null || true)"
      if [[ -n "\$desktop_id" ]]; then
        parsed="\$(parse_desktop_file "\$desktop_id" 2>/dev/null || true)"
        [[ -n "\$parsed" ]] && browser="\$parsed"
      fi
      
      # Fallback to xdg-mime if xdg-settings didn't work
      if [[ -z "\$browser" ]]; then
        desktop_id="\$(xdg-mime query default x-scheme-handler/http 2>/dev/null || true)"
        if [[ -n "\$desktop_id" ]]; then
          parsed="\$(parse_desktop_file "\$desktop_id" 2>/dev/null || true)"
          [[ -n "\$parsed" ]] && browser="\$parsed"
        fi
      fi
      ;;
  esac
fi

# 4. Fallback to known browsers
if [[ -z "\$browser" ]]; then
  IFS=',' read -ra fallback_list <<< "\$FALLBACKS"
  for b in "\${fallback_list[@]}"; do
    b="\${b#"\${b%%[![:space:]]*}"}"  # trim
    b="\${b%"\${b##*[![:space:]]}"}"  # trim
    if use_cmd "\$b"; then
      browser="\$b"
      break
    fi
  done
fi

# 5. Last resort: xdg-open
if [[ -z "\$browser" ]]; then
  if use_cmd xdg-open; then
    browser="xdg-open"
  fi
fi

[[ -n "\$browser" ]] || { echo "webapp-run: no supported browser found" >&2; exit 1; }

# Detect display server (Wayland vs X11)
detect_display_server() {
  # Check config override first
  case "\${WAYLAND_MODE:-auto}" in
    force) echo "wayland"; return 0 ;;
    x11) echo "x11"; return 0 ;;
    auto|*) ;;
  esac
  
  # Check WAYLAND_DISPLAY first (most reliable)
  if [[ -n "\${WAYLAND_DISPLAY:-}" ]]; then
    echo "wayland"
    return 0
  fi
  
  # Check XDG_SESSION_TYPE
  if [[ "\${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
    echo "wayland"
    return 0
  fi
  
  # Check for X11
  if [[ -n "\${DISPLAY:-}" ]] && [[ "\${DISPLAY}" != wayland-* ]]; then
    echo "x11"
    return 0
  fi
  
  # Default to wayland if no DISPLAY, otherwise x11
  if [[ -z "\${DISPLAY:-}" ]]; then
    echo "wayland"
  else
    echo "x11"
  fi
}

display_server="\$(detect_display_server)"

# Set up environment variables for Wayland
setup_wayland_env() {
  local browser_name="\$1"
  local display="\$2"
  
  if [[ "\$display" != "wayland" ]]; then
    return 0
  fi
  
  # Firefox Wayland support
  if [[ "\$browser_name" == *firefox* ]]; then
    export MOZ_ENABLE_WAYLAND=1
    # Also set for Firefox ESR and better performance
    export MOZ_WAYLAND_USE_VAAPI=1
    # Enable native Wayland for better integration
    export MOZ_DBUS_REMOTE=1
  fi
  
  # Chromium-based browsers usually auto-detect, but we can ensure it
  case "\$browser_name" in
    *chromium*|*chrome*|*brave*|*vivaldi*|*microsoft-edge*|*opera*|*thorium*|*zen-browser*)
      # Chromium-based browsers auto-detect Wayland, but we can ensure it
      # Don't override if already set (user might want X11)
      [[ -z "\${GDK_BACKEND:-}" ]] && export GDK_BACKEND=wayland
      # Enable native Wayland for Chromium
      export WAYLAND_DISPLAY="\${WAYLAND_DISPLAY:-wayland-0}"
      ;;
  esac
  
  # Qt-based browsers (like Falkon, Konqueror)
  case "\$browser_name" in
    *falkon*|*konqueror*)
      [[ -z "\${QT_QPA_PLATFORM:-}" ]] && export QT_QPA_PLATFORM=wayland,xcb
      ;;
  esac
  
  # Ensure XDG runtime directory is set (required for Wayland)
  [[ -z "\${XDG_RUNTIME_DIR:-}" ]] && export XDG_RUNTIME_DIR="/run/user/\$(id -u)"
}

# Setup environment for detected display server
setup_wayland_env "\$browser" "\$display_server"

# Determine if browser supports --app flag
supports_app=false
case "\$browser" in
  *chromium*|*chrome*|*brave*|*vivaldi*|*microsoft-edge*|*opera*|*thorium*|*zen-browser*) supports_app=true ;;
esac

# Build command arguments
if \$supports_app; then
  args=( "\$browser" --app="\$url" )
  [[ -n "\$wmclass" ]] && args+=( --class="\$wmclass" )
  [[ -n "\$profile" ]] && args+=( --user-data-dir="\$profile" )
  args+=( "\${extra[@]}" )
else
  args=( "\$browser" "\$url" "\${extra[@]}" )
fi

# Launch method selection (works for both X11 and Wayland)
launch_browser() {
  # Try uwsm first (works on both X11 and Wayland)
  if use_cmd uwsm; then
    exec setsid uwsm app -- "\${args[@]}"
    return
  fi
  
  # For Wayland, try compositor-specific launchers
  if [[ "\$display_server" == "wayland" ]]; then
    # Try wlr-randr or swaymsg to detect compositor
    local compositor=""
    
    # Detect Sway
    if [[ -n "\${SWAYSOCK:-}" ]] || pgrep -x sway >/dev/null 2>&1; then
      compositor="sway"
    # Detect Hyprland
    elif [[ -n "\${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || pgrep -x Hyprland >/dev/null 2>&1; then
      compositor="hyprland"
    # Detect KDE Plasma (Wayland)
    elif [[ "\${XDG_CURRENT_DESKTOP:-}" == *KDE* ]] && [[ "\${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
      compositor="kde"
    # Detect GNOME (Wayland)
    elif [[ "\${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] && [[ "\${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
      compositor="gnome"
    fi
    
    # For Wayland, setsid should work fine with most compositors
    # The browser will be launched and the compositor will handle window management
    if use_cmd setsid; then
      exec setsid "\${args[@]}"
    else
      exec "\${args[@]}"
    fi
  else
    # X11: use setsid or direct exec
    if use_cmd setsid; then
      exec setsid "\${args[@]}"
    else
      exec "\${args[@]}"
    fi
  fi
}

launch_browser
RUNNER
  chmod +x "$runner"
  echo "$runner"
}

# --------------------------- command parsing ---------------------------
VERBOSE=""
DRY_RUN=""
MODE="create"

show_help() {
  cat <<EOF
webapp-maker.sh - Create native launchers for web applications

USAGE:
  webapp-maker.sh [OPTIONS] [NAME] [URL] [ICON]
  webapp-maker.sh --list
  webapp-maker.sh --info <app-id>
  webapp-maker.sh --update <app-id> [OPTIONS]
  webapp-maker.sh --test <app-id>

COMMANDS:
  (none)              Create a new webapp launcher
  --list, -l          List all installed webapps
  --info <app-id>     Show details about a webapp
  --update <app-id>   Update an existing webapp
  --test <app-id>     Test launch a webapp
  --profiles          List all webapp profiles
  --clean-profiles    Remove orphaned profiles
  --export <app-id>   Export webapp configuration
  --backup             Backup all webapps
  --interactive, -i    Launch interactive TUI mode
  --help, -h          Show this help message

OPTIONS:
  --name NAME, -n     App name (for create/update)
  --url URL, -u       App URL (for create/update)
  --icon ICON, -i     Icon URL or local file path (for create/update)
  --verbose, -v       Show detailed output
  --dry-run           Preview changes without applying them

EXAMPLES:
  webapp-maker.sh "Gmail" "https://mail.google.com" "https://mail.google.com/favicon.ico"
  webapp-maker.sh --list
  webapp-maker.sh --info gmail
  webapp-maker.sh --update gmail --icon /path/to/icon.png
  webapp-maker.sh --test gmail

EOF
}

# Parse command-line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --list|-l)
        MODE="list"
        shift
        ;;
      --info|-i)
        MODE="info"
        APP_ID="$2"
        shift 2
        ;;
      --update|-u)
        MODE="update"
        APP_ID="$2"
        shift 2
        ;;
      --test|-t)
        MODE="test"
        APP_ID="$2"
        shift 2
        ;;
      --profiles)
        MODE="profiles"
        shift
        ;;
      --clean-profiles)
        MODE="clean-profiles"
        shift
        ;;
      --export)
        MODE="export"
        APP_ID="$2"
        shift 2
        ;;
      --backup)
        MODE="backup"
        shift
        ;;
      --interactive|--tui)
        MODE="tui"
        shift
        ;;
      --name|-n)
        name="$2"
        shift 2
        ;;
      --url|-u)
        site="$2"
        shift 2
        ;;
      --icon|-i)
        icon_url="$2"
        shift 2
        ;;
      --verbose|-v)
        VERBOSE=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        VERBOSE=1
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      --*)
        fail "Unknown option: $1 (use --help for usage)"
        ;;
      *)
        # Positional arguments: name, url, icon
        if [[ -z "${name:-}" ]]; then
          name="$1"
        elif [[ -z "${site:-}" ]]; then
          site="$1"
        elif [[ -z "${icon_url:-}" ]]; then
          icon_url="$1"
        else
          fail "Too many arguments (use --help for usage)"
        fi
        shift
        ;;
    esac
  done
}

# Read key from .desktop file
desktop_get() {
  local key="$1" file="$2" line=""
  line="$(grep -i -m1 "^${key}=" "$file" 2>/dev/null || true)"
  [[ -n "$line" ]] && printf '%s\n' "${line#*=}" || printf '%s' ""
}

# List all installed webapps
list_webapps() {
  info "Scanning $apps_dir for webapps..."
  shopt -s nullglob
  local count=0
  printf "%-30s %-50s %-20s\n" "ID" "Name" "Status"
  printf "%-30s %-50s %-20s\n" "$(printf '%.30s' "$(printf '%*s' 30)")" "$(printf '%.50s' "$(printf '%*s' 50)")" "$(printf '%.20s' "$(printf '%*s' 20)")" | tr ' ' '-'
  
  for f in "$apps_dir"/*.desktop; do
    [[ -f "$f" ]] || continue
    local base="$(basename "${f%.*}")"
    local exec_line="$(desktop_get Exec "$f")"
    
    # Only show webapps created by this tool
    if [[ -n "$exec_line" ]] && grep -qE 'webapp-run' <<<"$exec_line"; then
      local nm="$(desktop_get Name "$f")"
      local icon="$(desktop_get Icon "$f")"
      local status="OK"
      
      # Check if files exist
      [[ -f "$f" ]] || status="Missing .desktop"
      [[ -z "$icon" ]] || [[ -f "$icon" ]] || status="Missing icon"
      
      printf "%-30s %-50s %-20s\n" "$base" "${nm:-<unknown>}" "$status"
      ((count++))
    fi
  done
  
  if [[ $count -eq 0 ]]; then
    echo "No webapps found in $apps_dir"
  else
    echo ""
    echo "Total: $count webapp(s)"
  fi
}

# Show info about a webapp
show_info() {
  local app_id="$1"
  [[ -z "$app_id" ]] && fail "App ID required (use --list to see available apps)"
  
  local desktop_path="$apps_dir/${app_id}.desktop"
  [[ -f "$desktop_path" ]] || fail "Webapp not found: $app_id"
  
  local exec_line="$(desktop_get Exec "$desktop_path")"
  [[ -n "$exec_line" ]] && grep -qE 'webapp-run' <<<"$exec_line" || fail "Not a webapp-maker webapp: $app_id"
  
  local name="$(desktop_get Name "$desktop_path")"
  local icon="$(desktop_get Icon "$desktop_path")"
  local comment="$(desktop_get Comment "$desktop_path")"
  local wmclass="$(desktop_get StartupWMClass "$desktop_path")"
  
  # Extract URL and profile from Exec line
  local url=""
  local profile=""
  read -r -a exec_parts <<<"$exec_line"
  for ((i=0; i<${#exec_parts[@]}; i++)); do
    case "${exec_parts[$i]}" in
      --profile|--profile-dir|--user-data-dir)
        profile="${exec_parts[$i+1]}"
        ;;
      *)
        # URL is usually the last quoted argument
        if [[ "${exec_parts[$i]}" =~ ^https?:// ]]; then
          url="${exec_parts[$i]//\"/}"
        fi
        ;;
    esac
  done
  
  # Try to find profile if not in Exec
  if [[ -z "$profile" ]]; then
    profile="$profile_base_dir/$app_id"
  fi
  
  cat <<EOF
Webapp Information: $app_id
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Name:        $name
URL:         ${url:-<not found>}
Icon:        ${icon:-<not set>}
Profile:     ${profile:-<not set>}
WMClass:     ${wmclass:-<not set>}
Desktop:     $desktop_path

Files:
  Desktop:   $desktop_path $([ -f "$desktop_path" ] && echo "✓" || echo "✗")
  Icon:      ${icon:-N/A} $([ -n "$icon" ] && [ -f "$icon" ] && echo "✓" || echo "✗")
  Profile:   ${profile:-N/A} $([ -n "$profile" ] && [ -d "$profile" ] && echo "✓" || echo "✗")

EOF
}

# List all profiles
list_profiles() {
  info "Scanning $profile_base_dir for profiles..."
  shopt -s nullglob
  local count=0
  printf "%-30s %-50s %-15s\n" "Profile ID" "Associated App" "Size"
  printf "%-30s %-50s %-15s\n" "$(printf '%.30s' "$(printf '%*s' 30)")" "$(printf '%.50s' "$(printf '%*s' 50)")" "$(printf '%.15s' "$(printf '%*s' 15)")" | tr ' ' '-'
  
  for profile_dir in "$profile_base_dir"/*; do
    [[ -d "$profile_dir" ]] || continue
    local profile_id="$(basename "$profile_dir")"
    local desktop_path="$apps_dir/${profile_id}.desktop"
    local app_name="<orphaned>"
    
    if [[ -f "$desktop_path" ]]; then
      app_name="$(desktop_get Name "$desktop_path")"
    fi
    
    local size=""
    if have du; then
      size="$(du -sh "$profile_dir" 2>/dev/null | cut -f1)"
    else
      size="<unknown>"
    fi
    
    printf "%-30s %-50s %-15s\n" "$profile_id" "${app_name:-<unknown>}" "$size"
    ((count++))
  done
  
  if [[ $count -eq 0 ]]; then
    echo "No profiles found in $profile_base_dir"
  else
    echo ""
    echo "Total: $count profile(s)"
  fi
}

# Clean orphaned profiles (profiles without desktop files)
clean_profiles() {
  info "Scanning for orphaned profiles..."
  shopt -s nullglob
  local orphaned=()
  
  for profile_dir in "$profile_base_dir"/*; do
    [[ -d "$profile_dir" ]] || continue
    local profile_id="$(basename "$profile_dir")"
    local desktop_path="$apps_dir/${profile_id}.desktop"
    
    if [[ ! -f "$desktop_path" ]]; then
      orphaned+=("$profile_dir")
    fi
  done
  
  if [[ ${#orphaned[@]} -eq 0 ]]; then
    echo "No orphaned profiles found."
    return 0
  fi
  
  echo "Found ${#orphaned[@]} orphaned profile(s):"
  for profile in "${orphaned[@]}"; do
    echo "  - $profile"
  done
  
  echo ""
  if confirm "Remove these orphaned profiles?"; then
    for profile in "${orphaned[@]}"; do
      rm -rf "$profile"
      echo "Removed: $profile"
    done
    echo "Cleaned ${#orphaned[@]} orphaned profile(s)."
  else
    echo "Aborted."
  fi
}

# Export a webapp configuration
export_webapp() {
  local app_id="$1"
  [[ -z "$app_id" ]] && fail "App ID required"
  
  local desktop_path="$apps_dir/${app_id}.desktop"
  [[ -f "$desktop_path" ]] || fail "Webapp not found: $app_id"
  
  local name="$(desktop_get Name "$desktop_path")"
  local exec_line="$(desktop_get Exec "$desktop_path")"
  local icon="$(desktop_get Icon "$desktop_path")"
  
  # Extract URL from Exec
  local url=""
  read -r -a exec_parts <<<"$exec_line"
  for part in "${exec_parts[@]}"; do
    if [[ "$part" =~ ^https?:// ]]; then
      url="${part//\"/}"
      break
    fi
  done
  
  # Create export directory
  local export_dir="${XDG_DATA_HOME:-$HOME/.local/share}/webapp-maker/exports"
  mkdir -p "$export_dir"
  
  local export_file="$export_dir/${app_id}.json"
  local timestamp="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')"
  
  cat >"$export_file" <<EOF
{
  "app_id": "$app_id",
  "name": "$name",
  "url": "$url",
  "icon": "$icon",
  "exported_at": "$timestamp",
  "version": "1.0"
}
EOF
  
  echo "Exported webapp to: $export_file"
  
  # Also export per-app config if it exists
  local app_config="$apps_config_dir/${app_id}.ini"
  if [[ -f "$app_config" ]]; then
    cp "$app_config" "$export_dir/${app_id}.ini"
    echo "Exported config to: $export_dir/${app_id}.ini"
  fi
}

# Backup all webapps
backup_all() {
  local backup_dir="${XDG_DATA_HOME:-$HOME/.local/share}/webapp-maker/backups"
  local timestamp="$(date +%Y%m%d_%H%M%S 2>/dev/null || date '+%Y%m%d_%H%M%S')"
  local backup_path="$backup_dir/webapps_${timestamp}"
  
  mkdir -p "$backup_path"
  
  info "Backing up webapps to: $backup_path"
  
  # Backup desktop files
  shopt -s nullglob
  local count=0
  for f in "$apps_dir"/*.desktop; do
    local exec_line="$(desktop_get Exec "$f")"
    if [[ -n "$exec_line" ]] && grep -qE 'webapp-run' <<<"$exec_line"; then
      cp "$f" "$backup_path/"
      ((count++))
    fi
  done
  
  # Backup configs
  if [[ -d "$apps_config_dir" ]]; then
    mkdir -p "$backup_path/configs"
    cp -r "$apps_config_dir"/* "$backup_path/configs/" 2>/dev/null || true
  fi
  
  # Create manifest
  cat >"$backup_path/manifest.txt" <<EOF
Webapp Maker Backup
Created: $(date)
Total webapps: $count
Backup location: $backup_path
EOF
  
  echo "Backup complete: $backup_path"
  echo "  - $count desktop file(s)"
  echo "  - Config files (if any)"
}

# Test launch a webapp
test_launch() {
  local app_id="$1"
  [[ -z "$app_id" ]] && fail "App ID required"
  
  local desktop_path="$apps_dir/${app_id}.desktop"
  [[ -f "$desktop_path" ]] || fail "Webapp not found: $app_id"
  
  local exec_line="$(desktop_get Exec "$desktop_path")"
  [[ -n "$exec_line" ]] && grep -qE 'webapp-run' <<<"$exec_line" || fail "Not a webapp-maker webapp: $app_id"
  
  echo "Testing launch for: $app_id"
  echo "Exec command: $exec_line"
  echo ""
  echo "Launching in 2 seconds... (Ctrl+C to cancel)"
  sleep 2
  
  # Extract just the command part (before any % codes)
  local cmd="${exec_line%%%*}"
  eval "setsid $cmd" &
  echo "Launched! Check if the browser window opened."
}

# Initialize config and paths (called before command processing)
init_script() {
  load_config
  init_default_config
  init_paths
}

# --------------------------- initialize config ---------------------------
init_script

# Parse command-line arguments
name=""
site=""
icon_url=""
APP_ID=""
parse_args "$@"

# Handle different modes
case "$MODE" in
  list)
    list_webapps
    exit 0
    ;;
  info)
    show_info "$APP_ID"
    exit 0
    ;;
  test)
    test_launch "$APP_ID"
    exit 0
    ;;
  profiles)
    list_profiles
    exit 0
    ;;
  clean-profiles)
    clean_profiles
    exit 0
    ;;
  export)
    export_webapp "$APP_ID"
    exit 0
    ;;
  backup)
    backup_all
    exit 0
    ;;
# TUI main loop function (defined before case statement)
run_tui_main() {
  while true; do
    local main_choice
    main_choice=$(tui_menu "Webapp Maker - Main Menu" \
        "Create New Webapp" \
        "List Webapps" \
        "View Webapp Info" \
        "Update Webapp" \
        "Test Webapp Launch" \
        "Remove Webapp" \
        "Manage Profiles" \
        "Export/Backup" \
        "Exit")
      
      [[ -z "$main_choice" ]] && break
      
      case "$main_choice" in
        0)
          # Create - call script recursively with args
          local tui_name="" tui_site="" tui_icon=""
          tui_input tui_name "Enter app name:" || continue
          [[ -z "$tui_name" ]] && continue
          tui_input tui_site "Enter URL:" "https://" || continue
          [[ -z "$tui_site" ]] && continue
          tui_input tui_icon "Enter icon URL or file path:" || continue
          [[ -z "$tui_icon" ]] && continue
          
          if tui_confirm "Create webapp '$tui_name'?"; then
            # Exit TUI and call script with creation args
            exec "$0" "$tui_name" "$tui_site" "$tui_icon"
          fi
          ;;
        1)
          local output
          output=$(list_webapps)
          tui_msg "Installed Webapps" "$output"
          ;;
        2)
          local app_id
          app_id=$(tui_select_webapp "Select Webapp to View")
          [[ -z "$app_id" ]] && continue
          local output
          output=$(show_info "$app_id")
          tui_msg "Webapp Information" "$output"
          ;;
        3)
          local app_id
          app_id=$(tui_select_webapp "Select Webapp to Update")
          [[ -z "$app_id" ]] && continue
          
          local desktop_path="$apps_dir/${app_id}.desktop"
          local current_name="$(desktop_get Name "$desktop_path")"
          local current_url=""
          local exec_line="$(desktop_get Exec "$desktop_path")"
          read -r -a exec_parts <<<"$exec_line"
          for part in "${exec_parts[@]}"; do
            if [[ "$part" =~ ^https?:// ]]; then
              current_url="${part//\"/}"
              break
            fi
          done
          local current_icon="$(desktop_get Icon "$desktop_path")"
          
          local update_choice
          update_choice=$(tui_menu "Update Webapp: $current_name" \
            "Update Name" \
            "Update URL" \
            "Update Icon" \
            "Cancel")
          
          [[ -z "$update_choice" ]] && continue
          
          case "$update_choice" in
            0)
              local new_name
              tui_input new_name "Enter new name:" "$current_name" || continue
              exec "$0" --update "$app_id" --name "$new_name"
              ;;
            1)
              local new_url
              tui_input new_url "Enter new URL:" "$current_url" || continue
              exec "$0" --update "$app_id" --url "$new_url"
              ;;
            2)
              local new_icon
              tui_input new_icon "Enter new icon URL or path:" "$current_icon" || continue
              exec "$0" --update "$app_id" --icon "$new_icon"
              ;;
            3) continue ;;
          esac
          ;;
        4)
          local app_id
          app_id=$(tui_select_webapp "Select Webapp to Test")
          [[ -z "$app_id" ]] && continue
          if tui_confirm "Launch webapp '$app_id' for testing?"; then
            test_launch "$app_id"
            tui_msg "Test Launch" "Webapp launched. Check if the browser window opened."
          fi
          ;;
        5)
          local app_id
          app_id=$(tui_select_webapp "Select Webapp to Remove")
          [[ -z "$app_id" ]] && continue
          local desktop_path="$apps_dir/${app_id}.desktop"
          local app_name="$(desktop_get Name "$desktop_path")"
          if tui_confirm "Remove webapp '$app_name' ($app_id)?"; then
            if [[ -f "./webapp-remover.sh" ]]; then
              ./webapp-remover.sh "$app_id" --yes
            elif [[ -f "$(dirname "$0")/webapp-remover.sh" ]]; then
              "$(dirname "$0")/webapp-remover.sh" "$app_id" --yes
            else
              rm -f "$desktop_path"
              tui_msg "Removed" "Webapp '$app_name' has been removed."
            fi
          fi
          ;;
        6)
          local profile_choice
          profile_choice=$(tui_menu "Profile Management" \
            "List Profiles" \
            "Clean Orphaned Profiles" \
            "Back")
          [[ -z "$profile_choice" ]] && continue
          case "$profile_choice" in
            0)
              local output
              output=$(list_profiles)
              tui_msg "Webapp Profiles" "$output"
              ;;
            1)
              if tui_confirm "Remove orphaned profiles?"; then
                clean_profiles
                tui_msg "Cleanup Complete" "Orphaned profiles have been removed."
              fi
              ;;
            2) continue ;;
          esac
          ;;
        7)
          local export_choice
          export_choice=$(tui_menu "Export & Backup" \
            "Export Single Webapp" \
            "Backup All Webapps" \
            "Back")
          [[ -z "$export_choice" ]] && continue
          case "$export_choice" in
            0)
              local app_id
              app_id=$(tui_select_webapp "Select Webapp to Export")
              [[ -z "$app_id" ]] && continue
              export_webapp "$app_id"
              tui_msg "Export Complete" "Webapp exported successfully."
              ;;
            1)
              if tui_confirm "Backup all webapps?"; then
                backup_all
                tui_msg "Backup Complete" "All webapps have been backed up."
              fi
              ;;
            2) continue ;;
          esac
          ;;
        8) break ;;
      esac
    done
}

# Continue with update mode handling
if [[ "$MODE" == "update" ]]; then
    # Update mode - will be handled below
    [[ -z "$APP_ID" ]] && fail "App ID required for --update (use --list to see available apps)"
    desktop_path="$apps_dir/${APP_ID}.desktop"
    [[ -f "$desktop_path" ]] || fail "Webapp not found: $APP_ID"
    
    # Load existing values
    name="${name:-$(desktop_get Name "$desktop_path")}"
    # Extract URL from Exec if not provided
    if [[ -z "${site:-}" ]]; then
      exec_line="$(desktop_get Exec "$desktop_path")"
      read -r -a exec_parts <<<"$exec_line"
      for part in "${exec_parts[@]}"; do
        if [[ "$part" =~ ^https?:// ]]; then
          site="${part//\"/}"
          break
        fi
      done
    fi
    # Keep existing icon if not updating
    if [[ -z "${icon_url:-}" ]]; then
      icon_url="$(desktop_get Icon "$desktop_path")"
      [[ "$icon_url" == "$icons_dir/"* ]] && icon_url=""  # Will reuse existing
    fi
fi

# Continue with create mode if needed
if [[ "$MODE" == "create" ]]; then
    # Create mode - continue with normal flow
    if [[ -z "${name:-}" || -z "${site:-}" || -z "${icon_url:-}" ]]; then
      echo "Web App Forge — create a launcher"
      [[ -z "${name:-}" ]] && ask name "App name" "My Web App"
      [[ -z "${site:-}" ]] && ask site "URL" "https://example.org"
      [[ -z "${icon_url:-}" ]] && ask icon_url "Icon URL or path" "https://example.org/icon.png"
    fi
fi

[[ -n "$name" && -n "$site" && -n "$icon_url" ]] || fail "name, URL, and icon are required"

# --------------------------- validate and fix URL ---------------------------
validate_url() {
  local url="$1"
  
  # Auto-add https:// if missing
  if [[ ! "$url" =~ ^https?:// ]]; then
    warn "URL missing protocol, assuming https://"
    url="https://$url"
  fi
  
  # Basic URL validation
  if [[ ! "$url" =~ ^https?://[a-zA-Z0-9] ]]; then
    warn "URL format looks suspicious: $url"
  fi
  
  # Remove trailing slashes for cleaner URLs
  url="${url%%/}"
  
  echo "$url"
}

site="$(validate_url "$site")"
info "Using URL: $site"

# Safe identifier for filenames / WMClass
if [[ "$MODE" == "update" ]]; then
  id="$APP_ID"
else
  id="$(sanitize_id "$name")"
  [[ -n "$id" ]] || fail "could not derive a safe ID from name"
fi

# Load per-app config if it exists
load_app_config "$id"

# Get config values
wmclass_prefix="$(get_config_value "app_wmclass_prefix" 2>/dev/null || echo "webapp-")"
extra_flags="$(get_config_value "app_extra_flags" 2>/dev/null || echo "")"

# Build paths
desktop_path="$apps_dir/${id}.desktop"
icon_path="$icons_dir/${id}.png"
profile_dir="$profile_base_dir/${id}"
wm_class="${wmclass_prefix}${id}"

if [[ "$MODE" == "update" ]]; then
  info "Updating webapp: $id"
  [[ -f "$desktop_path" ]] || fail "Desktop file not found: $desktop_path"
else
  info "Creating webapp: $id"
fi

if [[ -n "$DRY_RUN" ]]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "DRY RUN MODE - No changes will be made"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "App ID:      $id"
  echo "Name:        $name"
  echo "URL:         $site"
  echo "Icon:        $icon_url"
  echo "Desktop:     $desktop_path"
  echo "Icon path:   $icon_path"
  echo "Profile:     $profile_dir"
  echo "WMClass:     $wm_class"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
fi

mkdir -p "$profile_dir"

# --------------------------- handle icon ---------------------------
handle_icon() {
  local source="$1"
  local dest="$2"
  
  info "Processing icon: $source"
  
  # Check if source is a local file
  if [[ -f "$source" ]]; then
    info "Using local icon file: $source"
    
    # Validate it's an image file
    if have file; then
      local file_type
      file_type="$(file -b --mime-type "$source" 2>/dev/null || echo "")"
      if [[ ! "$file_type" =~ ^image/ ]]; then
        warn "File doesn't appear to be an image (detected: $file_type)"
        warn "Continuing anyway..."
      else
        info "Icon type: $file_type"
      fi
    fi
    
    # Determine destination extension based on source
    local source_ext="${source##*.}"
    local dest_ext="${dest##*.}"
    
    # If source is SVG, try to convert it
    if [[ "${source_ext,,}" == "svg" ]] && [[ "${dest_ext,,}" != "svg" ]]; then
      info "SVG icon detected, attempting conversion..."
      local converted=0
      
      # Try inkscape
      if have inkscape && [[ "$dest_ext" == "png" ]]; then
        if inkscape --export-type=png --export-filename="$dest" "$source" 2>/dev/null; then
          converted=1
          info "Converted SVG to PNG using inkscape"
        fi
      fi
      
      # Try rsvg-convert
      if [[ $converted -eq 0 ]] && have rsvg-convert && [[ "$dest_ext" == "png" ]]; then
        if rsvg-convert -o "$dest" "$source" 2>/dev/null; then
          converted=1
          info "Converted SVG to PNG using rsvg-convert"
        fi
      fi
      
      # Try convert (ImageMagick)
      if [[ $converted -eq 0 ]] && have convert; then
        if convert "$source" "$dest" 2>/dev/null; then
          converted=1
          info "Converted SVG to PNG using ImageMagick"
        fi
      fi
      
      if [[ $converted -eq 0 ]]; then
        warn "Could not convert SVG, copying as-is (may not work in all desktops)"
        cp "$source" "$dest" || fail "Failed to copy icon"
      fi
    else
      # Copy the file (preserving format or converting extension)
      cp "$source" "$dest" || fail "Failed to copy icon"
    fi
    
    # Validate copied icon
    if [[ ! -s "$dest" ]]; then
      fail "Icon file is empty after copy: $dest"
    fi
    
    return 0
  fi
  
  # Otherwise, treat as URL
  if [[ ! "$source" =~ ^https?:// ]]; then
    warn "Icon source doesn't look like a URL or file path: $source"
    warn "Attempting to download anyway..."
  fi
  
  info "Downloading icon from: $source"
  
  if have curl; then
    curl -fsSL -o "$dest" "$source" || fail "failed to download icon from: $source"
  elif have wget; then
    wget -qO "$dest" "$source" || fail "failed to download icon from: $source"
  else
    fail "need curl or wget to download icon"
  fi
  
  # Validate downloaded icon
  if [[ ! -s "$dest" ]]; then
    fail "Downloaded icon is empty: $dest"
  fi
  
  # Try to validate it's actually an image
  if have file; then
    local file_type
    file_type="$(file -b --mime-type "$dest" 2>/dev/null || echo "")"
    if [[ ! "$file_type" =~ ^image/ ]]; then
      warn "Downloaded file doesn't appear to be an image (detected: $file_type)"
      warn "It may not display correctly in your desktop environment"
    else
      info "Downloaded icon type: $file_type"
    fi
  fi
}

handle_icon "$icon_url" "$icon_path"

# --------------------------- install runner ---------------------------
runner_path="$(install_launcher "$id")"

# --------------------------- write desktop entry ---------------------------
# Build exec command with extra flags if configured
exec_cmd="$runner_path --profile \"$profile_dir\" --wmclass \"$wm_class\" \"$site\""
if [[ -n "$extra_flags" ]]; then
  exec_cmd="$exec_cmd $extra_flags"
fi

cat >"$desktop_path" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Comment=$name
Exec=$exec_cmd
Icon=$icon_path
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;Utility;
StartupWMClass=$wm_class
EOF

chmod 0644 "$desktop_path"

# Best-effort desktop/icon db refresh
if have desktop-file-validate; then
  if ! desktop-file-validate "$desktop_path" 2>/dev/null; then
    warn "Desktop file validation failed (may still work)"
  fi
fi
have update-desktop-database && update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
icon_cache_dir="$(dirname "$icons_dir")"
have gtk-update-icon-cache && gtk-update-icon-cache -q "$icon_cache_dir" >/dev/null 2>&1 || true

# Success message
if [[ "$MODE" == "update" ]]; then
  printf '\n✓ Updated launcher successfully!\n'
  printf '  Desktop file: %s\n' "$desktop_path"
  printf '  Icon:         %s\n' "$icon_path"
  printf '  Profile:      %s\n' "$profile_dir"
  printf '  App name:     %s\n' "$name"
  printf '\nThe webapp should appear in your application menu shortly.\n'
  printf 'If it doesn\'t appear, try: update-desktop-database %s\n' "$apps_dir"
else
  printf '\n✓ Created launcher successfully!\n'
  printf '  Desktop file: %s\n' "$desktop_path"
  printf '  Icon:         %s\n' "$icon_path"
  printf '  Profile:      %s\n' "$profile_dir"
  printf '  App name:     %s\n' "$name"
  printf '\nThe webapp should appear in your application menu shortly.\n'
  printf 'If it doesn\'t appear, try: update-desktop-database %s\n' "$apps_dir"
fi
