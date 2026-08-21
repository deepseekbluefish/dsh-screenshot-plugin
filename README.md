# dsh-screenshot-plugin

DeepSeek Harness 界面内的**微信式一键框选截屏**插件：对话输入框左侧多一个 ✂ 按钮，点一下全屏变暗、拖动框选区域即可截取。

- 松手后**选区保留**：可拖动移动、拖四角/四边手柄缩放，双击或按 Enter 确认截取
- PNG 自动编号（`截屏N_HHmm.png`）存入指定目录
- 标记 `[Shot N HH:mm]` 自动写入输入框（发送后 agent 可按标记定位文件读取）
- 纯 ASCII 标记，无编码坑

## 安装

```sh
dsh plugin --profile web add github:deepseekbluefish/dsh-screenshot-plugin
```

重启 DSH（或对应客户端）后，输入框左侧出现 ✂ 按钮。

## 使用

1. 点 **✂** → 屏幕变暗
2. 拖动框选区域；**松手后选区保留**——可拖动选区移动、拖四角/四边手柄缩放
3. **双击选区（或按 Enter）确认截取**，Esc 取消
4. 输入框自动出现 `[Shot N HH:mm]`
5. 点发送，把标记发给 agent（配合视觉插件如 [ModLens](https://github.com/liustack/modlens)，agent 可直接读取该截图）

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
- **截图保存了但输入框没标记？** 查看按钮弹出的提示（成功/失败都有提示）。标记是纯 ASCII `[Shot N HH:mm]`，可手动发送。
- **agent 怎么读截图？** 发送标记后，配了视觉引擎的 agent（如 ModLens）可按编号与时间定位 `截屏N_HHmm.png`。
- **文件名为什么带"截屏"而标记是 ASCII？** 文件名便于在文件夹中辨认；标记用 ASCII 是为了避免聊天输入/传输中的编码问题。

## License

[MIT](LICENSE)
