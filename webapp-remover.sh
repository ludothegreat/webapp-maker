#!/bin/bash
# webapp-remover: simple, interactive remover for web-app launchers
set -euo pipefail

say(){ printf '%s\n' "$*"; }
warn(){ printf 'warning: %s\n' "$*" >&2; }
fail(){ printf 'error: %s\n' "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

# --------------------------- configuration ---------------------------
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/webapp-maker"
global_config="$config_dir/config.ini"

# Default configuration values
declare -A CONFIG
CONFIG[paths_desktop_dir]=""
CONFIG[paths_icon_dir]=""
CONFIG[paths_profile_dir]=""

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

# Get config value with fallback chain: env var > global config > default
get_config_value() {
  local key="$1"
  local env_key="WEBAPP_$(echo "$key" | tr '[:lower:]' '[:upper:]' | tr '_' '_')"
  
  # Check environment variable first
  if [[ -n "${!env_key:-}" ]]; then
    printf '%s' "${!env_key}"
    return 0
  fi
  
  # Check global config
  if [[ -n "${CONFIG["$key"]:-}" ]]; then
    printf '%s' "${CONFIG["$key"]}"
    return 0
  fi
  
  return 1
}

# Load config and initialize paths
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"

# Load global config if it exists
if [[ -f "$global_config" ]]; then
  load_config_file "$global_config" || true
fi

# Get paths from config or use defaults
desktop_dir_config="$(get_config_value "paths_desktop_dir" 2>/dev/null || echo "")"
apps_dir="${desktop_dir_config:-$data_dir/applications}"

icon_dir_config="$(get_config_value "paths_icon_dir" 2>/dev/null || echo "")"
icons_dir="${icon_dir_config:-$data_dir/icons/hicolor/256x256/apps}"

profile_dir_config="$(get_config_value "paths_profile_dir" 2>/dev/null || echo "")"
profile_base_dir="${profile_dir_config:-$data_dir/webapps}"

alt_icons_dir="$apps_dir/icons"   # legacy icon path
mkdir -p "$apps_dir"

# ID rule (matches your maker): lower+underscores, ASCII collation
sanitize_id() {
  local s
  s=$(printf '%s' "$1" | LC_ALL=C tr '[:upper:] ' '[:lower:]_')
  LC_ALL=C tr -cd '[:alnum:]_.-' <<<"$s"
}

# Read key from .desktop (safe: returns empty if missing)
desktop_get() {
  local key="$1" file="$2" line=""
  line="$(grep -i -m1 "^${key}=" "$file" 2>/dev/null || true)"
  [[ -n "$line" ]] && printf '%s\n' "${line#*=}" || printf '%s' ""
}

# Y/N prompt
confirm() { local a; read -rp "$1 [y/N]: " a; [[ "${a,,}" == y || "${a,,}" == yes ]]; }

# Desktop/icon cache refresh (best-effort)
refresh_db() {
  have desktop-file-validate && desktop-file-validate "$1" >/dev/null 2>&1 || true
  have update-desktop-database && update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
  have gtk-update-icon-cache && gtk-update-icon-cache -q "$data_dir/icons" >/dev/null 2>&1 || true
}

# Classifier
FORGE_PAT='webapp-run'
COMPAT_PAT='webapp-launch|omarchy-launch-webapp|--app='
bucket() {
  local exec_line="$1" icon="$2"
  if [[ -n "$exec_line" ]] && grep -qE "$FORGE_PAT" <<<"$exec_line"; then echo forge; return; fi
  if [[ -n "$exec_line" ]] && grep -qE "$COMPAT_PAT" <<<"$exec_line"; then echo compat; return; fi
  if [[ "$icon" == "$icons_dir/"* || "$icon" == "$alt_icons_dir/"* ]]; then echo candidate; return; fi
  if [[ -n "$exec_line" ]] && grep -qE -- '--profile|--user-data-dir' <<<"$exec_line" && (grep -qi "$profile_base_dir/" <<<"$exec_line" || grep -qi "$data_dir/webapps/" <<<"$exec_line"); then
    echo candidate; return
  fi
  echo other
}

list_all() {
  shopt -s nullglob
  local shown=false pf=false pc=false pd=false
  for fpath in "$apps_dir"/*.desktop; do
    [[ -f "$fpath" ]] || continue
    local exec_line; exec_line="$(desktop_get Exec "$fpath")"
    local nm;       nm="$(desktop_get Name "$fpath")"
    local ic;       ic="$(desktop_get Icon "$fpath")"
    local base;     base="$(basename "${fpath%.*}")"
    local kind;     kind="$(bucket "$exec_line" "$ic")"
    case "$kind" in
      forge)
        $pf || { say "Forge launchers:"; pf=true; }
        printf '  • %s   (id: %s)\n' "${nm:-<unknown>}" "$base"; shown=true;;
      compat)
        $pc || { say ""; say "Compatible launchers:"; pc=true; }
        printf '  • %s   (id: %s)\n' "${nm:-<unknown>}" "$base"; shown=true;;
      candidate)
        $pd || { say ""; say "Candidates:"; pd=true; }
        printf '  • %s   (id: %s)\n' "${nm:-<unknown>}" "$base"; shown=true;;
      *) : ;;
    esac
  done
  if ! $shown; then
    say "No web-app style launchers detected in $apps_dir"
  else
    say ""
    say "Tip: ./webapp-remover.sh <Name or id>"
  fi
}

# ---------- UX: mostly flagless ----------
auto_yes=false
auto_purge=false
# Accept optional flags for scripting, but you can ignore them
for arg in "$@"; do
  case "$arg" in
    --yes) auto_yes=true ;;
    --purge) auto_purge=true ;;
  esac
done

# Strip the optional flags from $@
set -- $(printf '%s\n' "$@" | tr ' ' '\n' | grep -vE '^--(yes|purge)$' || true)

# 0 args → list; 1 arg → treat as name/id
if [[ $# -eq 0 ]]; then
  list_all
  exit 0
elif [[ $# -gt 1 ]]; then
  fail "Use: webapp-remover.sh [<Name or id>] [--yes] [--purge]"
fi

target_input="$1"

# Find matches by Name= (case-insensitive), id (basename), or fuzzy contains
shopt -s nullglob
matches=()
for f in "$apps_dir"/*.desktop; do
  nm="$(desktop_get Name "$f")"
  base="$(basename "${f%.*}")"
  if [[ "${nm,,}" == "${target_input,,}" || "${base,,}" == "${target_input,,}" ]]; then
    matches+=("$f")
  fi
done
# If not found, try contains (case-insensitive)
if [[ ${#matches[@]} -eq 0 ]]; then
  for f in "$apps_dir"/*.desktop; do
    nm="$(desktop_get Name "$f")"
    base="$(basename "${f%.*}")"
    if [[ "${nm,,}" == *"${target_input,,}"* || "${base,,}" == *"${target_input,,}"* ]]; then
      matches+=("$f")
    fi
  done
fi

[[ ${#matches[@]} -gt 0 ]] || fail "No match for \"$target_input\" in $apps_dir"

# If multiple, prompt to pick
if [[ ${#matches[@]} -gt 1 ]]; then
  say "Multiple matches for \"$target_input\":"
  i=1
  for f in "${matches[@]}"; do
    nm="$(desktop_get Name "$f")"; base="$(basename "${f%.*}")"
    printf "  %d) %s   (id: %s)\n" "$i" "$nm" "$base"
    ((i++))
  done
  while true; do
    read -rp "Select 1-${#matches[@]}: " pick
    [[ "$pick" =~ ^[0-9]+$ && "$pick" -ge 1 && "$pick" -le ${#matches[@]} ]] && break
  done
  desktop_path="${matches[$((pick-1))]}"
else
  desktop_path="${matches[0]}"
fi

# Gather details
exec_line="$(desktop_get Exec "$desktop_path")"
icon_path="$(desktop_get Icon "$desktop_path")"
nm="$(desktop_get Name "$desktop_path")"
id="$(basename "${desktop_path%.*}")"
kind="$(bucket "$exec_line" "$icon_path")"

# Fallback icon paths
if [[ -z "${icon_path:-}" ]]; then
  [[ -f "$icons_dir/${id}.png" ]] && icon_path="$icons_dir/${id}.png"
  [[ -z "${icon_path:-}" && -f "$alt_icons_dir/${id}.png" ]] && icon_path="$alt_icons_dir/${id}.png"
fi

# Try to detect profile dir from Exec; otherwise guess
profile_dir=""
if [[ -n "$exec_line" ]]; then
  read -r -a argv <<<"$exec_line"
  for ((i=0;i<${#argv[@]}-1;i++)); do
    case "${argv[$i]}" in
      --profile|--profile-dir|--user-data-dir) profile_dir="${argv[$i+1]}"; break;;
    esac
  done
fi
if [[ -z "$profile_dir" ]]; then
  for guess in "$profile_base_dir/$id" "$profile_base_dir/$nm" "$data_dir/webapps/$id" "$data_dir/webapps/$nm"; do
    [[ -d "$guess" ]] && profile_dir="$guess" && break
  done
fi

# Show plan
say "Will remove:"
say "  Name:    $nm"
say "  ID:      $id"
say "  Desktop: $desktop_path"
[[ -n "${icon_path:-}" ]] && say "  Icon:    $icon_path"
[[ -n "${profile_dir:-}" ]] && say "  Profile: $profile_dir"

# Warn on non-forge kinds (but no flags required)
case "$kind" in
  compat) warn "This looks like an older/compatible entry."; warn "Proceed only if you created it."; ;;
  candidate) warn "This looks like a candidate (heuristic)."; warn "Proceed only if you’re sure."; ;;
  *) : ;;
esac

# Confirm removal
if ! $auto_yes && ! confirm "Remove desktop entry${icon_path:+ and icon}?"; then
  say "Aborted."; exit 0
fi

# Optional purge prompt
if [[ -n "${profile_dir:-}" && $auto_purge == false ]]; then
  if confirm "Also remove profile data at: $profile_dir ?"; then auto_purge=true; fi
fi

# Do the removal
rm -f -- "$desktop_path"
[[ -n "${icon_path:-}" && -f "$icon_path" ]] && rm -f -- "$icon_path"
if $auto_purge && [[ -n "${profile_dir:-}" && -d "$profile_dir" ]]; then
  rm -rf -- "$profile_dir"
fi

refresh_db "$desktop_path"
say "Removed web app: $nm  (id: $id)"
