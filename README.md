# webapp maker

Turn any website into a native-looking Linux app.

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

## Possible 
