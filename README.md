# Rescale — native Windows app (Rust)

Rescale is a lightweight Windows resolution switcher for stretched gaming resolutions. The GUI and display switching are implemented in native Rust/Win32: **no PowerShell, Electron, webview, .NET or runtime downloads**.

## Features
- Read the **primary** display mode and capture it as the desktop resolution.
- Set custom game width and height, or choose one of the original eight presets.
- Save `rescale.config.json` in the executable folder (compatible with the original script's JSON keys).
- Test a game/desktop switch immediately.
- Create `Switch to Game Resolution.bat` and `Switch to Desktop Resolution.bat` shortcuts when saving.
- Run `rescale.exe --game`, `rescale.exe --desktop`, or `rescale.exe --configure` (also accepts `-Game` and `-Desktop`).

## Build on Windows
Install Rust via https://rustup.rs/ and run:

```powershell
cargo build --release
```

Your app is `target\release\rescale.exe`. Or use the **Build Windows app** GitHub Action and download its artifact.

## Usage
1. Open `rescale.exe`.
2. Capture your desktop resolution (automatically populated the first time).
3. Enter a game resolution or select a preset.
4. Save settings and shortcuts.
5. Double-click either shortcut or use the GUI buttons to switch.

**Important:** A custom resolution must already exist in your graphics driver (NVIDIA Control Panel / CRU). The app preserves the current refresh rate and color depth, matching the original PowerShell behavior. If a mode fails, create it in your driver first. Changes affect the primary display only.

**Portable configuration:** Keep `rescale.exe` in a writable directory (not `Program Files`) so the configuration and shortcut files can be saved next to it. On the first run, you can copy an existing `rescale.config.json` beside the EXE.

## Branding / dark theme
The Windows interface uses a charcoal palette, blue accent button, dark title bar and custom-drawn buttons. The Rescale logo is in `assets/rescale-logo.png`; the Windows executable icon is embedded from `assets/rescale.ico` at build time. The `embed-resource` build dependency requires an initial crates.io download.
