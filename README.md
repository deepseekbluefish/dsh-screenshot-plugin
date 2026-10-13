# dsh-screenshot-plugin

DeepSeek Harness 界面内的**微信式一键框选截屏**插件：对话输入框左侧多一个 ✂ 按钮，点一下全屏变暗、拖动框选区域即可截取。

- 松手后**选区保留**：可拖动移动、拖四角/四边手柄缩放，双击或按 Enter 确认截取
- PNG 自动编号（`截屏N_HHmm.png`）存入指定目录
- **截图同时复制进 Windows 剪贴板**：回到输入框按一次 **Ctrl+V**，图片就以缩略图形式进入草稿，可直接发送
- **不再改写你的输入框草稿**：旧版会把已经打好的字顶掉、并且只允许保留一个标记；现在可以边打字边连续粘多张截图

## 多语言简介 / Intro

- **简体中文**：微信式一键框选截屏插件：拖动框选、8 个手柄微调，Enter 确认截取、Esc 取消；PNG 自动编号保存，截图同时复制到剪贴板（回到输入框按 Ctrl+V 即可粘贴成图片）。已在 DeepSeek Harness Desktop 实测。
- **繁體中文**：微信式一鍵框選截圖外掛：拖曳框選、8 個控點微調，Enter 確認截取、Esc 取消；PNG 自動編號儲存，截圖同時複製到剪貼簿（回到輸入框按 Ctrl+V 即可貼上圖片）。已在 DeepSeek Harness Desktop 實測。
- **English**: WeChat-style one-click screenshot plugin: drag to select, fine-tune with 8 resize handles; press Enter to capture, Esc to cancel. PNGs are auto-numbered and the shot is copied to the clipboard (press Ctrl+V in the composer to paste it as an image). Tested on DeepSeek Harness Desktop.
- **Русский**: Плагин скриншотов в стиле WeChat: выделите область перетаскиванием, подправьте с помощью 8 маркеров; Enter — снять скриншот, Esc — отмена. PNG сохраняются с автонумерацией, снимок копируется в буфер обмена (Ctrl+V в поле ввода). Проверено на DeepSeek Harness Desktop.
- **Français** : Capture d'écran façon WeChat : sélectionnez à la souris, ajustez avec 8 poignées ; Entrée pour capturer, Échap pour annuler. PNG numérotés automatiquement et capture copiée dans le presse-papiers (Ctrl+V dans la zone de saisie). Testé sur DeepSeek Harness Desktop.
- **Italiano**: Plugin di screenshot stile WeChat: seleziona trascinando, regola con 8 maniglie; Invio per catturare, Esc per annullare. PNG con numerazione automatica e scatto copiato negli appunti (Ctrl+V nel campo di input). Testato su DeepSeek Harness Desktop.
- **日本語**: WeChat 風のワンクリックスクリーンショットプラグイン：ドラッグで範囲選択、8 つのハンドルで微調整。Enter で撮影、Esc でキャンセル。PNG は自動連番で保存され、撮影内容はクリップボードにコピーされます（入力欄で Ctrl+V）。DeepSeek Harness Desktop で動作確認済み。
- **한국어**: WeChat 스타일 원클릭 스크린샷 플러그인: 드래그로 영역 선택, 8개 핸들로 미세 조정. Enter로 캡처, Esc로 취소. PNG 자동 번호 저장, 캡처 이미지는 클립보드에 복사됩니다 (입력창에서 Ctrl+V). DeepSeek Harness Desktop에서 테스트 완료.

## 安装

```sh
dsh plugin --profile web add github:deepseekbluefish/dsh-screenshot-plugin
```

重启 DSH（或对应客户端）后，输入框左侧出现 ✂ 按钮。

## 使用

1. 点 **✂** → 屏幕变暗
2. 拖动框选区域；**松手后选区保留**——可拖动选区移动、拖四角/四边手柄缩放
3. **双击选区（或按 Enter）确认截取**，Esc 取消
4. 截图已存盘，**同时已复制到剪贴板**
5. 回到输入框按 **Ctrl+V** —— 图片以缩略图出现；可以继续打字，也可以再截一张继续粘（想粘几张粘几张），然后点发送。
   这条链路走 DSH 自己的粘贴通道，不需要任何视觉插件（本机模型原生支持图片输入，2026-10-13 实测）

## 配置

截图保存目录默认 `~/Pictures/DSH-Screenshots`，通过 profile 补丁覆盖：

```yaml
# ~/.dsh/profiles/<name>/cordis.patch.yml
- id: screenshot
  config:
    folder: 'D:\MyScreenshots'
```

## 工作原理

- **客户端**（`client/index.js`）：注册到 `conversation.input.left` slot 的 ✂ 按钮，点击后 `POST /api/screenshot/capture`
- **宿主**（`lib/index.js`）：注册 `webServer` 路由，拉起 PowerShell 全屏框选覆盖层，返回 `{ ok, file, marker }`
- **截屏脚本**（`lib/capture.ps1`）：WinForms 遮罩层（接收全部输入）+ 点击穿透的顶层绿色框架层（明绿 3px 框线 + 8 个缩放手柄 + 操作提示），`CopyFromScreen` 区域截取；纯 ASCII 源码（Windows PowerShell 5.1 编码安全）；结果从主流程输出；内置 `-SelfTest` 几何自检
- **填入输入框**：按优先级走 `props.inputActions` → `sessions.provideInfo(...).props.inputActions` → `session.prompt(..., 'queue')` 兜底，任何失败只弹提示、不影响使用

## 限制

- 仅 Windows（依赖 Windows PowerShell / System.Drawing）
- 宿主侧按钮点击与框选在应用前台进行；多显示器支持虚拟屏整体坐标

## 常见问题

- **点了按钮没反应？** 确认在会话输入框左侧能看到 ✂；该按钮走宿主路由，TUI/无 webServer 的部署不会显示。
- **截图后按 Ctrl+V 没粘出图？** 看按钮弹出的提示：写着"已复制到剪贴板"就说明图在剪贴板里，可能被其它剪贴板软件抢占了，等一秒再按一次；提示里给了文件路径，也可以手动打开该 PNG 复制。PNG 一定在截图文件夹里。
- **agent 怎么读这张图？** 两条路都行：① 你 Ctrl+V 粘贴发送，我直接看图；② 你把文件名告诉我，我用 `read_image` 读磁盘上的 `截屏N_HHmm.png`。**都不需要视觉插件**。
- **文件名为什么是"截屏N_HHmm"？** 文件名便于在文件夹中辨认与排序；保存目录可在配置里改（见上）。

## License

[MIT](LICENSE)
