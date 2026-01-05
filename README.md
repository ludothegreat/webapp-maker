# webapp-maker

Create native launcher applications for web services with isolated browser profiles, configurable settings, and full Wayland/X11 support.

Demo:
![Demo](https://github.com/ludothegreat/webapp-maker/releases/download/webapp-maker_gif/webapp-maker.gif)

## Features

- **Simple CLI** - Create webapp launchers with a single command
- **Icon Support** - Download from URL or use local files (PNG, SVG, etc.)
- **Fully Configurable** - Global and per-app configuration files
- **Smart Browser Detection** - Auto-detects your default browser with fallbacks
- **Wayland & X11 Support** - Works on Sway, Hyprland, KDE Plasma, GNOME, and more
- **Isolated Profiles** - Each webapp gets its own browser profile
- **Management Tools** - List, update, test, export, and backup webapps
- **Icon Validation** - Validates icons and auto-converts SVG to PNG
- **Smart Categories** - Auto-detects desktop file categories based on URL

## Installation

1. Clone or download this repository:
```bash
git clone <repository-url>
cd webapp-maker
```

2. Make the scripts executable:
```bash
chmod +x webapp-maker.sh webapp-remover.sh
```

3. (Optional) Add to your PATH:
```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$PATH:/path/to/webapp-maker"
```

## Quick Start

Create your first webapp:
```bash
./webapp-maker.sh "Gmail" "https://mail.google.com" "https://mail.google.com/favicon.ico"
```

Or use local icon:
```bash
./webapp-maker.sh "Gmail" "https://mail.google.com" "/path/to/icon.png"
```

The webapp will appear in your application menu!

## Usage

### Creating Webapps

**Interactive mode** (prompts for input):
```bash
./webapp-maker.sh
```

**Command-line mode**:
```bash
./webapp-maker.sh "App Name" "https://example.com" "https://example.com/icon.png"
```

**With options**:
```bash
./webapp-maker.sh --name "My App" --url "https://example.com" --icon "/path/to/icon.png"
```

### Listing Webapps

```bash
./webapp-maker.sh --list
# or
./webapp-maker.sh -l
```

Output shows:
- App ID
- App Name
- Status (OK, Missing icon, etc.)

### Getting Webapp Information

```bash
./webapp-maker.sh --info <app-id>
# Example:
./webapp-maker.sh --info gmail
```

Shows detailed information including:
- Name, URL, Icon path
- Profile directory
- WMClass
- File status

### Updating Webapps

Update any aspect of an existing webapp:
```bash
# Update icon
./webapp-maker.sh --update gmail --icon /new/icon.png

# Update URL
./webapp-maker.sh --update gmail --url "https://new-url.com"

# Update name
./webapp-maker.sh --update gmail --name "New Name"
```

### Testing Webapps

Test if a webapp launches correctly:
```bash
./webapp-maker.sh --test <app-id>
```

### Profile Management

List all profiles:
```bash
./webapp-maker.sh --profiles
```

Clean orphaned profiles (profiles without desktop files):
```bash
./webapp-maker.sh --clean-profiles
```

### Export & Backup

Export a single webapp:
```bash
./webapp-maker.sh --export <app-id>
# Exports to ~/.local/share/webapp-maker/exports/
```

Backup all webapps:
```bash
./webapp-maker.sh --backup
# Backs up to ~/.local/share/webapp-maker/backups/
```

### Other Options

**Verbose mode** (detailed output):
```bash
./webapp-maker.sh --verbose "App" "https://..." "icon.png"
# or
./webapp-maker.sh -v "App" "https://..." "icon.png"
```

**Dry-run mode** (preview without making changes):
```bash
./webapp-maker.sh --dry-run "App" "https://..." "icon.png"
```

## Configuration

### Global Configuration

The global config file is located at:
```
~/.config/webapp-maker/config.ini
```

A default config file is created automatically on first run. See `config.ini.example` for a template with all available options.

### Per-App Configuration

Create per-app configs at:
```
~/.config/webapp-maker/apps/<app-id>.ini
```

Example (`~/.config/webapp-maker/apps/gmail.ini`):
```ini
[browser]
command=firefox

[app]
extra_flags=--enable-features=VaapiVideoDecoder
```

### Configuration Options

#### `[browser]` Section
- `command` - Explicit browser command (e.g., "firefox", "chromium")
- `detection_method` - "auto", "xdg-settings", or "desktop-file"
- `fallbacks` - Comma-separated list of fallback browsers
- `wayland_mode` - "auto", "force", or "x11"

#### `[paths]` Section
- `desktop_dir` - Desktop file directory
- `icon_dir` - Icon directory
- `profile_dir` - Profile directory base
- `bin_dir` - Binary/launcher directory

#### `[app]` Section
- `icon_size` - Default icon size (for future use)
- `wmclass_prefix` - WMClass prefix (default: "webapp-")
- `extra_flags` - Additional browser flags (space-separated)

### Environment Variables

You can override config values with environment variables:
```bash
WEBAPP_BROWSER_COMMAND=firefox ./webapp-maker.sh "App" "https://..." "icon.png"
WEBAPP_PATHS_DESKTOP_DIR=/custom/path ./webapp-maker.sh ...
```

## Icon Support

### URL Icons
```bash
./webapp-maker.sh "App" "https://example.com" "https://example.com/icon.png"
```

### Local File Icons
```bash
./webapp-maker.sh "App" "https://example.com" "/path/to/icon.png"
```

### Supported Formats
- PNG (recommended)
- SVG (auto-converted to PNG if converters available)
- Other image formats (as supported by your desktop environment)

The script automatically:
- Detects if input is a file path or URL
- Validates downloaded/copied icons
- Converts SVG to PNG (using inkscape, rsvg-convert, or ImageMagick)
- Checks file types for validity

## Browser Support

### Auto-Detection
The script automatically detects your default browser using:
1. `xdg-settings get default-web-browser`
2. Desktop file parsing
3. Fallback browser list

### Supported Browsers
- **Chromium-based**: Chromium, Chrome, Brave, Vivaldi, Edge, Opera, Thorium, Zen Browser
- **Firefox**: Firefox, Firefox ESR
- **Qt-based**: Falkon, Konqueror
- **Fallback**: xdg-open

### Per-App Browser Override
Set a specific browser for an app via per-app config:
```ini
# ~/.config/webapp-maker/apps/myapp.ini
[browser]
command=firefox
```

## Wayland Support

Full support for Wayland compositors:
- **Sway** - Detected via `SWAYSOCK`
- **Hyprland** - Detected via `HYPRLAND_INSTANCE_SIGNATURE`
- **KDE Plasma** - Detected via `XDG_CURRENT_DESKTOP`
- **GNOME** - Detected via `XDG_CURRENT_DESKTOP`
- **Other wlroots-based** - Works with any wlroots compositor

The script automatically:
- Detects Wayland vs X11
- Sets appropriate environment variables for browsers
- Configures Firefox, Chromium, and Qt browsers for Wayland

## Desktop File Categories

Categories are auto-detected based on URL domain:
- Email services → `Office;Email;`
- Google Docs/Drive → `Office;`
- GitHub/GitLab → `Development;`
- Video sites → `AudioVideo;`
- Chat apps → `Network;InstantMessaging;`
- And more...

## Removing Webapps

Use the included remover script:
```bash
./webapp-remover.sh <app-id>
# or
./webapp-remover.sh <app-name>
```

Interactive mode:
```bash
./webapp-remover.sh
# Lists all webapps, then prompts for selection
```

Options:
- `--yes` - Skip confirmation prompts
- `--purge` - Also remove profile data

## Examples

### Create a Gmail webapp
```bash
./webapp-maker.sh "Gmail" "https://mail.google.com" "https://mail.google.com/favicon.ico"
```

### Create with local icon
```bash
./webapp-maker.sh "Discord" "https://discord.com/app" "/home/user/.local/share/icons/discord.png"
```

### Create with custom browser
```bash
# Set in config first, or use env var
WEBAPP_BROWSER_COMMAND=firefox ./webapp-maker.sh "App" "https://..." "icon.png"
```

### Update existing webapp
```bash
./webapp-maker.sh --update gmail --icon /new/icon.png
```

### List and manage
```bash
# List all
./webapp-maker.sh --list

# Get details
./webapp-maker.sh --info gmail

# Test launch
./webapp-maker.sh --test gmail

# Backup everything
./webapp-maker.sh --backup
```

## File Locations

### Default Paths (XDG-compliant)
- **Desktop files**: `~/.local/share/applications/`
- **Icons**: `~/.local/share/icons/hicolor/256x256/apps/`
- **Profiles**: `~/.local/share/webapps/<app-id>/`
- **Launcher script**: `~/.local/bin/webapp-run`
- **Config**: `~/.config/webapp-maker/config.ini`
- **Per-app configs**: `~/.config/webapp-maker/apps/<app-id>.ini`

All paths are configurable via the config file.

## Troubleshooting

### Browser not found
- Check your default browser: `xdg-settings get default-web-browser`
- Set explicit browser in config: `command=firefox`
- Check fallback browsers are installed

### Icon not displaying
- Verify icon file exists and is readable
- Check icon format (PNG recommended)
- Run: `gtk-update-icon-cache ~/.local/share/icons`
- Try: `update-desktop-database ~/.local/share/applications`

### Wayland issues
- Verify `WAYLAND_DISPLAY` is set: `echo $WAYLAND_DISPLAY`
- Check `XDG_SESSION_TYPE`: `echo $XDG_SESSION_TYPE`
- Force Wayland in config: `wayland_mode=force`

### Desktop file not appearing
- Run: `update-desktop-database ~/.local/share/applications`
- Check desktop file validity: `desktop-file-validate <file.desktop>`
- Verify file permissions: `chmod 644 <file.desktop>`

### Verbose debugging
Use `--verbose` flag for detailed output:
```bash
./webapp-maker.sh --verbose "App" "https://..." "icon.png"
```

## Requirements

- Bash 4.0+
- `curl` or `wget` (for downloading icons)
- `xdg-utils` (for browser detection, recommended)
- Desktop environment that supports `.desktop` files

Optional (for enhanced features):
- `inkscape`, `rsvg-convert`, or `convert` (ImageMagick) - for SVG conversion
- `file` - for icon validation
- `desktop-file-validate` - for desktop file validation
- `update-desktop-database` - for desktop database updates
- `gtk-update-icon-cache` - for icon cache updates

## License

[OBSD](LICENSE) - This project is provided as-is, without warranty. You are responsible for complying with applicable laws and regulations.

## Contributing

Contributions welcome! Please feel free to submit issues or pull requests. By contributing, you agree that your contributions will be licensed under the 0BSD license.
