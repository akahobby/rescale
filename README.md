# ResolutionTool

ResolutionTool is a Windows utility for quickly switching between your native desktop resolution and a custom in-game resolution.

It is especially useful when NVIDIA Control Panel does not allow creating custom resolutions on your display setup.

## Included files

- `app/scripts/rescale.ps1` — main PowerShell CLI
- `app/config/settings.json` — stores native and game profiles (`width`, `height`, `bitDepth`)
- `rescale.bat` — quick launcher for the config flow
- generated launcher `.bat` files (created by the `config` command)

## First-time setup

1. Open the project folder.
2. Run the config command:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\app\scripts\rescale.ps1 config
   ```
   Or run `rescale.bat`.
3. Enter your desired game resolution.
4. Click **Save and apply**.
5. Restart Windows once after the first `NV_Modes` update.

During setup, the tool will:

- save your game resolution to config
- apply NVIDIA `NV_Modes`
- regenerate launcher `.bat` files

## Commands

```powershell
# show help
powershell -ExecutionPolicy Bypass -File .\app\scripts\rescale.ps1 help

# switch to game resolution
powershell -ExecutionPolicy Bypass -File .\app\scripts\rescale.ps1 game

# restore native resolution
powershell -ExecutionPolicy Bypass -File .\app\scripts\rescale.ps1 native

# apply NV_Modes (admin required)
powershell -ExecutionPolicy Bypass -File .\app\scripts\rescale.ps1 fix-nvidia

# optional multi-monitor mode helpers
powershell -ExecutionPolicy Bypass -File .\app\scripts\rescale.ps1 gaming-mode
powershell -ExecutionPolicy Bypass -File .\app\scripts\rescale.ps1 normal-mode

# show current + configured resolutions
powershell -ExecutionPolicy Bypass -File .\app\scripts\rescale.ps1 status
```

## Generated launchers

The config command generates launchers in:

- `app/launchers/ResolutionTool Config.bat`
- `app/launchers/Enable Custom Resolution.bat`
- `app/launchers/Restore Native Resolution.bat`
- project root: `Enable Custom Resolution.bat`
- project root: `Restore Native Resolution.bat`

## Config window improvements

The `config` window includes quality-of-life upgrades:

- numeric resolution controls (no manual number parsing errors)
- preset picker (current/native/common stretched values)
- one-click **Use current display**
- live aspect-ratio and size-vs-native preview
- clearer progress/status text while saving

## Performance and reliability updates

- `NV_Modes.ps1` now targets the display adapter class keys directly instead of recursively scanning the full registry class tree.
- External tool calls now validate process exit codes, so launcher/UI flows fail fast with a clear error when something goes wrong.

## Suggested stretched resolutions (common for 1440p)

- `2100 x 1440`
- `1566 x 1080`
- `1280 x 880`

Use any resolution your GPU/display supports.

## Troubleshooting

If your custom resolution does not appear:

1. Open **Device Manager** (`Win + X` → Device Manager).
2. Expand **Monitors**.
3. Disable unused monitor entries.
4. Restart your PC.

## Compatibility

- NVIDIA GPUs: supported
- AMD GPUs: not officially supported

## License

MIT (see `LICENSE`).
