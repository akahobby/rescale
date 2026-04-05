# Rescale

Small Windows utility to switch the **primary** display between a saved desktop resolution and a custom game resolution (for example stretched modes).

Uses the Win32 display APIs (`ChangeDisplaySettingsEx`). The mode must already be exposed by your GPU driver (NVIDIA Control Panel custom resolutions, CRU, etc.).

## Files

| File | Purpose |
|------|---------|
| `rescale.ps1` | Main script: configuration UI, `-Game`, `-Desktop` (downloaded automatically if missing) |
| `rescale.bat` | All you need to start: fetches `rescale.ps1` from this repo when absent, then runs it |

After you save settings in the UI, the script creates:

- `Switch to Game Resolution.bat`
- `Switch to Desktop Resolution.bat`

(Those generated files are ignored by git.)

## First run

1. Keep only `rescale.bat` (or clone the whole repo).
2. Double-click it. The first run downloads `rescale.ps1` from GitHub into the same folder if it is missing.
3. Capture your desktop resolution, set the game size (presets available), then **Save config and create .bat files**.

## Command line

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File .\rescale.ps1 -Game
powershell -NoProfile -ExecutionPolicy Bypass -File .\rescale.ps1 -Desktop
powershell -NoProfile -ExecutionPolicy Bypass -File .\rescale.ps1 -Configure
```

## License

MIT. See [LICENSE](LICENSE).
