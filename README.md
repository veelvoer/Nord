<h1 align=center>Nord Shell</h1>

<div align=center>

A customized [Quickshell](https://quickshell.outfoxxed.me) desktop shell for [Hyprland](https://hyprland.org).

</div>

## Installation

### Dependencies

- [`quickshell-git`](https://quickshell.outfoxxed.me)
- [`ddcutil`](https://github.com/rockowitz/ddcutil)
- [`brightnessctl`](https://github.com/Hummer12007/brightnessctl)
- [`libcava`](https://github.com/LukashonakV/cava)
- [`networkmanager`](https://networkmanager.dev)
- [`lm-sensors`](https://github.com/lm-sensors/lm-sensors)
- [`fish`](https://github.com/fish-shell/fish-shell)
- [`aubio`](https://github.com/aubio/aubio)
- [`libpipewire`](https://pipewire.org)
- [`libqalculate`](https://github.com/Qalculate/libqalculate)
- `glibc`, `qt6-base`, `qt6-declarative`, `gcc-libs`
- [`material-symbols`](https://fonts.google.com/icons)
- [`caskaydia-cove-nerd`](https://www.nerdfonts.com/font-downloads)
- [`swappy`](https://github.com/jtheoof/swappy)
- [`bash`](https://www.gnu.org/software/bash)

Build dependencies:

- [`cmake`](https://cmake.org)
- [`ninja`](https://github.com/ninja-build/ninja)

### Setup

```sh
cd $XDG_CONFIG_HOME/quickshell
git clone https://github.com/veelvoer/Nord.git nord

cd nord
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/
cmake --build build
sudo cmake --install build
```

## Usage

Start the shell with:

```sh
qs -c nord
```

## Configuration

All configuration options are in `~/.config/nord/shell.json`. Create this file manually to customize the shell. See the [Caelestia documentation](https://github.com/caelestia-dots/shell#configuring) for all available options.

### Shortcuts

Keybinds are configured via Hyprland [global shortcuts](https://wiki.hyprland.org/Configuring/Binds/#dbus-global-shortcuts).

### Wallpapers

Wallpapers are read from `~/Pictures/Wallpapers` by default. Change the path in `~/.config/nord/shell.json` under `paths.wallpaperDir`.

### Profile Picture

The dashboard profile picture is read from `~/.face`.

## Credits

Based on [Caelestia Shell](https://github.com/caelestia-dots/shell) by soramane.
