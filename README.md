# dsh-screenshot-plugin

DeepSeek Harness 界面内的**微信式一键框选截屏**插件：对话输入框左侧多一个 ✂ 按钮，点一下全屏变暗、拖动框选区域，松手即截取。

- PNG 自动编号（`截屏N_HHmm.png`）存入指定目录
- 标记 `[Shot N HH:mm]` 自动写入输入框（发送后 agent 可按标记定位文件读取）
- 纯 ASCII 标记，无编码坑

## 安装

```sh
dsh plugin --profile web add github:<owner>/dsh-screenshot-plugin
```

重启 DSH（或对应客户端）后，输入框左侧出现 ✂ 按钮。

## 使用

1. 点 **✂** → 屏幕变暗
2. 拖动框选区域，松手截取（Esc 取消）
3. 输入框自动出现 `[Shot N HH:mm]`
4. 点发送，把标记发给 agent（配合视觉插件如 [ModLens](https://github.com/liustack/modlens)，agent 可直接读取该截图）

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
- **截屏脚本**（`lib/capture.ps1`）：WinForms 覆盖层 + `CopyFromScreen` 区域截取，纯 ASCII 源码（Windows PowerShell 5.1 编码安全），结果从主流程输出
- **填入输入框**：按优先级走 `props.inputActions` → `sessions.provideInfo(...).props.inputActions` → `session.prompt(..., 'queue')` 兜底，任何失败只弹提示、不影响使用

## 限制

- 仅 Windows（依赖 Windows PowerShell / System.Drawing）
- 宿主侧按钮点击与框选在应用前台进行；多显示器支持虚拟屏整体坐标

## License

[MIT](LICENSE)

## ��������

- **���˰�ťû��Ӧ��** ȷ���ڻỰ���������ܿ��� ?���ð�ť������·�ɣ�TUI/�� webServer �Ĳ��𲻻���ʾ��
- **��ͼ�����˵������û��ǣ�** �鿴��ť��������ʾ���ɹ�/ʧ�ܶ�����ʾ��������Ǵ� ASCII `[Shot N HH:mm]`�����ֶ����͡�
- **agent ��ô����ͼ��** ���ͱ�Ǻ������Ӿ������ agent���� ModLens���ɰ������ʱ�䶨λ `����N_HHmm.png`��
- **�ļ���Ϊʲô��"����"������� ASCII��** �ļ����������ļ����б��ϣ������ ASCII ��Ϊ�˱�����������/�����еı������⡣
