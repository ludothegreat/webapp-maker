# webapp maker
Turn any website into a native-looking Linux app.
![Animated GIF showing how webapp-maker works.](webapp-maker.gif)

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
## Optional: add shell aliases for quick access

Run these from the folder where the scripts live so `$PWD` points to the right path.

### Bashrc
```bash
printf '\n# webapp maker aliases\nalias webapp-make="%s/webapp-maker.sh"\nalias webapp-remove="%s/webapp-remover.sh"\n' "$PWD" "$PWD" >> ~/.bashrc && . ~/.bashrc
```

### Zshrc
```bash
printf '\n# webapp maker aliases\nalias webapp-make="%s/webapp-maker.sh"\nalias webapp-remove="%s/webapp-remover.sh"\n' "$PWD" "$PWD" >> ~/.zshrc && source ~/.zshrc
```

### If you feel lucky, auto-detect your shell
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

## License
... Do what ever you want with it. There is no license.

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
