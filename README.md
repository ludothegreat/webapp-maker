# webapp maker
Turn any website into a native-looking Linux app.
![Demo](https://github.com/ludothegreat/webapp-maker/releases/download/webapp-maker_gif/webapp-maker.gif)

`webapp-maker.sh` creates a `.desktop` launcher with icon and its own browser profile.  
`webapp-remover.sh` lists and removes web apps interactively.

> Inspired by [Omarchy](https://github.com/basecamp/omarchy)'s web app maker tool; rewritten from scratch for portability.  
> [Check out all of DHH's work on Omarchy. This project is REALLY cool: ](https://omarchy.org/)

## Features
- Creates a web app windows (Chromium family via `--app=<URL>`; Firefox fallback).
- All web apps are per-profile (`~/.local/share/webapps/<id>`).
- App icons under XDG hicolor theme (256×256).
- No one off library deps: Bash + `curl` **or** `wget`. Optional: `xdg-settings`, `update-desktop-database`, `gtk-update-icon-cache`.
- Browser detection: Chromium/Chrome/Brave/Vivaldi/Edge/Opera/Thorium → Firefox → `xdg-open`.
- Simple remover script.

## Requirements
- Linux desktop with freedesktop `.desktop` support.
- Browser (Chromium family preferred; Firefox works too).
- One of: `curl` or `wget`.
- .png icon (suggest using [https://dashboardicons.com/](https://dashboardicons.com/))

## Install
Clone the repo and make the scripts executable:
```bash
git clone https://github.com/<your-username>/webapp-maker.git
cd webapp-maker
chmod +x webapp-maker.sh webapp-remover.sh
```
On first use, the maker installs a small helper at:
```
~/.local/bin/webapp-run
```

## Quick start
Interactive:
```bash
./webapp-maker.sh
```

Non-interactive:
```
./webapp-maker.sh "<App Name>" "<App URL>" "<Icon PNG URL or file:///absolute/path/icon.png"
```
Example:
```
./webapp-maker.sh "Microsoft Teams" "https://teams.microsoft.com/v2/" \
  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/microsoft-teams.png"
```

You’ll see something like:
```
Created launcher:
  ~/.local/share/applications/teams.desktop
Icon:
  ~/.local/share/icons/hicolor/256x256/apps/teams.png
Run from your app menu as: Teams
```
Optional: add shell aliases for quick access

Run these from the folder where the scripts live so `$PWD` points to the right path.

Bashrc
```bash
printf '\n# webapp maker aliases\nalias webapp-make="%s/webapp-maker.sh"\nalias webapp-remove="%s/webapp-remover.sh"\n' "$PWD" "$PWD" >> ~/.bashrc && . ~/.bashrc
```

Zshrc
```bash
printf '\n# webapp maker aliases\nalias webapp-make="%s/webapp-maker.sh"\nalias webapp-remove="%s/webapp-remover.sh"\n' "$PWD" "$PWD" >> ~/.zshrc && source ~/.zshrc
```

If you feel lucky, auto-detect your shell - it has some quarks sometimes.
```bash
rc="$([ -n "$ZSH_VERSION" ] && echo ~/.zshrc || { [ -n "$BASH_VERSION" ] && echo ~/.bashrc || echo ~/.bashrc; })"; printf '\n# webapp maker aliases\nalias webapp-make="%s/webapp-maker.sh"\nalias webapp-remove="%s/webapp-remover.sh"\n' "$PWD" "$PWD" >> "$rc" && { [ -n "$ZSH_VERSION" ] && source ~/.zshrc || [ -n "$BASH_VERSION" ] && . ~/.bashrc || :; }
```

After that, you can simply run:
```bash
webapp-make
webapp-remove
```



## Removing apps (no flags to memorize)
List everything:
```bash
./webapp-remover.sh
```

Remove by **name** or **id** (interactive confirmations; will offer to purge profile data):
```bash
./webapp-remover.sh "Microsoft Teams"
# or
./webapp-remover.sh teams
```

_Optional (non-interactive)_: `--yes` to auto-confirm, `--purge` to delete profile data too:
```bash
./webapp-remover.sh "Microsoft Teams" --yes --purge
```

## What goes where?
- **Launchers**: `~/.local/share/applications/<id>.desktop`
- **Icons**: `~/.local/share/icons/hicolor/256x256/apps/<id>.png`
- **Per-app profiles**: `~/.local/share/webapps/<id>`
- **Helper**: `~/.local/bin/webapp-run`

## How it works
- **webapp-maker.sh** sanitizes the name → `<id>`, downloads the icon, writes the `.desktop`, and ensures `webapp-run` exists.
- **webapp-run** picks your browser; Chromium family launches with `--app=<URL>` (plus `--user-data-dir` and `--class`), Firefox opens the URL normally.
- **webapp-remover.sh** lists launchers, lets you pick one, removes the `.desktop` and icon, and can purge the profile.

## Troubleshooting: 
### Wrong app opens instead of your browser:

If launching a web app opens **some other program** (e.g., a remote-desktop client) instead of your browser, your system’s **MIME defaults** for `http/https` (and/or `text/html`) are most likely pointing to the wrong `.desktop` file.

### 1) Diagnose
Check what your system thinks the default web browser is and which app handles web links:
```bash
xdg-settings get default-web-browser 2>/dev/null || echo "(xdg-settings not available)"
xdg-mime query default x-scheme-handler/http
xdg-mime query default x-scheme-handler/https
xdg-mime query default text/html
```
If any of those show something that’s **not your browser** (e.g., `rustdesk.desktop`), that’s the issue.

### 2) Find your browser’s desktop ID
Look up the `.desktop` file for your browser (examples: `brave-browser.desktop`, `chromium.desktop`, `google-chrome.desktop`, `vivaldi-stable.desktop`, `microsoft-edge.desktop`, `opera.desktop`, `firefox.desktop`, `librewolf.desktop`, etc.):
```bash
grep -Ril 'Exec=.*<browser-binary>' /usr/share/applications ~/.local/share/applications 2>/dev/null
# examples:
#   <browser-binary> = brave-browser | chromium | google-chrome | vivaldi-stable | microsoft-edge | opera | firefox | librewolf
```
Note the filename you find, e.g. `brave-browser.desktop`. We’ll call it `<YOUR_BROWSER.desktop>` below.

### 3) Set your browser as the default handler
```bash
xdg-mime default <YOUR_BROWSER.desktop> x-scheme-handler/http
xdg-mime default <YOUR_BROWSER.desktop> x-scheme-handler/https
xdg-mime default <YOUR_BROWSER.desktop> text/html
xdg-settings set default-web-browser <YOUR_BROWSER.desktop> 2>/dev/null || true
update-desktop-database ~/.local/share/applications 2>/dev/null || true
```

### 4) Verify and sanity test
```bash
xdg-mime query default x-scheme-handler/http
xdg-mime query default x-scheme-handler/https
xdg-mime query default text/html
# → all three should print <YOUR_BROWSER.desktop>

xdg-open https://example.com   # should now open your browser
```

### 5) If it still opens the wrong app
User config files may have pinned an override. Replace any bad entries:
```bash
grep -Ei 'x-scheme-handler/(http|https)|text/html' \
  ~/.config/mimeapps.list ~/.local/share/applications/mimeapps.list 2>/dev/null

# replace a wrong handler (example: rustdesk.desktop) with your browser:
sed -i 's/rustdesk\.desktop/<YOUR_BROWSER.desktop>/g' \
  ~/.config/mimeapps.list ~/.local/share/applications/mimeapps.list 2>/dev/null || true
```
Alternative using GLib’s tool:
```bash
gio mime x-scheme-handler/http  <YOUR_BROWSER.desktop>
gio mime x-scheme-handler/https <YOUR_BROWSER.desktop>
gio mime text/html              <YOUR_BROWSER.desktop>
```

### 6) Optional: help the launcher pick your browser explicitly
If your environment is minimal (tiling WM, no DE), it can help to set `$BROWSER`:
```bash
# temporary for this shell:
export BROWSER=<browser-binary>    # e.g., brave-browser, chromium, firefox

# persistent:
echo 'export BROWSER=<browser-binary>' >> ~/.profile
```
Then log out/in (or source your profile) and try launching the web app again.

> Tip: If you use **dmenu_run**, it doesn’t read `.desktop` files. Use `i3-dmenu-desktop` or `rofi -show drun`, or create small wrappers in `~/.local/bin` that call `gtk-launch <id>` so `dmenu_run` can list them.


## License
0BSD ... Do what ever you want with it.

## Credits
DHH -  [Omarchy](https://omarchy.org/)

## To-Do / Ideas (possible add-ons)

These scripts are **not** included by default, but are ideas I might add later.

### 1) Batch remove by substring (`webapp-remove-matching.sh`)
Remove any launchers whose **Name** or **id** contains a substring (case-insensitive). Prompt for confirmation then calls `webapp-remover.sh` for each match.

**Example**
```bash
# plan: remove everything with "google" in the name/id
./webapp-remove-matching.sh google
```

### 2) One-off migrator from old entries (`webapp-migrate-one.sh`)
Recreate an older/compatible `.desktop` as a new **webapp maker** entry (using `webapp-run`), then remove the old one.

**Example**
```bash
# migrate a single legacy launcher into the new format
./webapp-migrate-one.sh "$HOME/.local/share/applications/Basecamp.desktop"
```

> If these are interesting to you, open an issue or PR.
