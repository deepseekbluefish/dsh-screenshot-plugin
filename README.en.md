# dsh-screenshot-plugin

A WeChat-style in-app screenshot button for DeepSeek Harness: a small ✂ button next to the composer input. Click it, drag a region on the dimmed screen, release — captured.

- PNGs auto-numbered (`JiePingN_HHmm.png`) into a configurable folder
- A `[Shot N HH:mm]` marker is written into the composer input (send it and your agent can locate and read the file)
- Pure-ASCII marker, no encoding pitfalls

## Install

```sh
dsh plugin --profile web add github:<owner>/dsh-screenshot-plugin
```

Restart DSH (or your client) and the ✂ button appears next to the composer input.

## Usage

1. Click **✂** — the screen dims
2. Drag to select a region, release to capture (Esc cancels)
3. `[Shot N HH:mm]` appears in the input box
4. Send it — with a vision plugin such as [ModLens](https://github.com/liustack/modlens) your agent can read the screenshot

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
- **Host** (`lib/index.js`): registers a `webServer` route, spawns a PowerShell full-screen region-select overlay, returns `{ ok, file, marker }`
- **Capture script** (`lib/capture.ps1`): WinForms overlay + `CopyFromScreen` region capture; strictly ASCII source (Windows PowerShell 5.1 encoding safety); the JSON result is emitted from the main flow, not from event handlers
- **Composer fill**: tries `props.inputActions`, then `sessions.provideInfo(...).props.inputActions`, falling back to `session.prompt(..., 'queue')`; failures surface as a toast and never break the app

## Limitations

- Windows only (depends on Windows PowerShell / System.Drawing)
- Multi-monitor supported via the virtual-screen coordinate space

## License

[MIT](LICENSE)
