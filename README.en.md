# dsh-screenshot-plugin

A WeChat-style in-app screenshot button for DeepSeek Harness: a small ✂ button next to the composer input. Click it, drag a region on the dimmed screen, release — captured.

- PNGs auto-numbered (`JiePingN_HHmm.png`) into a configurable folder
- The shot is copied to the Windows clipboard — press **Ctrl+V** in the composer and it lands as a visible image attachment
- Your composer draft is never rewritten, so you can keep typing and paste several shots in a row

## Install

```sh
dsh plugin --profile web add github:<owner>/dsh-screenshot-plugin
```

Restart DSH (or your client) and the ✂ button appears next to the composer input.

## Usage

1. Click **✂** — the screen dims
2. Drag to draw a selection; **the frame stays after release** — drag inside to move it, drag the 8 edge/corner handles to resize
3. **Double-click the selection (or press Enter) to capture**, Esc cancels
4. The shot is saved **and copied to the clipboard**
5. Press **Ctrl+V** in the composer — the image appears as a thumbnail. Keep typing, capture more shots and paste those too, then send. This uses the host's own paste path: **no vision plugin is needed** (the model takes image input natively, verified 2026-10-13).

## Configuration

Shots save to `~/Pictures/DSH-Screenshots` by default. Override per profile:

```yaml
# ~/.dsh/profiles/<name>/cordis.patch.yml
- id: screenshot
  config:
    folder: 'D:\MyScreenshots'
```

## How it works

- **Client** (`client/index.js`): a ✂ button registered in the `conversation.input.left` slot; clicking it POSTs to `/api/screenshot/capture`
- **Host** (`lib/index.js`): registers a `webServer` route, spawns a PowerShell full-screen region-select overlay, returns `{ ok, file, path, marker, clipboard }`
- **Capture script** (`lib/capture.ps1`): WinForms overlay + `CopyFromScreen` region capture; saves the PNG, then puts the shot on the Windows clipboard as Bitmap **and** PNG (Chromium only honours the `PNG` format); strictly ASCII source (Windows PowerShell 5.1 encoding safety); the JSON result is emitted from the main flow, not from event handlers
- **Clipboard, not the draft**: the client half never touches the composer draft. Earlier versions called `inputActions.setDraft(marker)`, which replaced the whole draft — typed text was lost and only one shot could be held. Ctrl+V now rides the host's own paste path, so the plugin no longer injects `sessions` either.

## Limitations

- Windows only (depends on Windows PowerShell / System.Drawing)
- Multi-monitor supported via the virtual-screen coordinate space

## License

[MIT](LICENSE)
