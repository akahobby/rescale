# Rescale

Small Windows utility to switch the **primary** display between a saved desktop resolution and a custom game resolution (for example stretched modes).

Uses the Win32 display APIs (`ChangeDisplaySettingsEx`). The mode must already be exposed by your GPU driver (NVIDIA Control Panel custom resolutions, CRU, etc.).

## Files

| File | Purpose |
|------|---------|
| `rescale.ps1` | Main script: configuration UI, `-Game`, `-Desktop` |
| `rescale.bat` | Opens the setup window |

After you save settings in the UI, the script creates:

- `Switch to Game Resolution.bat`
- `Switch to Desktop Resolution.bat`

(Those generated files are ignored by git.)

## First run

1. Clone or download this folder.
2. Double-click `rescale.bat` (or run `rescale.ps1` with no arguments).
3. Capture your desktop resolution, set the game size (presets available), then **Save config and create .bat files**.

## Command line

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File .\rescale.ps1 -Game
powershell -NoProfile -ExecutionPolicy Bypass -File .\rescale.ps1 -Desktop
powershell -NoProfile -ExecutionPolicy Bypass -File .\rescale.ps1 -Configure
```

## License

MIT. See [LICENSE](LICENSE).
