/**
 * dsh-screenshot-plugin — 客户端半段
 *
 * 在对话输入框左侧注入一个截屏小按钮：
 * 点击 → POST /api/screenshot/capture（宿主拉起全屏框选截屏）
 *      → 宿主把图放进 Windows 剪贴板（Bitmap + PNG）并存盘
 *      → 用户按 Ctrl+V 把图粘贴进输入框（宿主自带的粘贴路径），发送即可。
 *
 * 为什么要改（2026-10-13）：
 *   旧版用 inputActions.setDraft(marker) 把标记写进草稿。setDraft 是「整段替换」，
 *   后果是 ① 用户截图前打的字会被顶掉 ② 只能保留一个标记（第二次截图又整段替换）。
 *   现在不再碰草稿，也就不再依赖 setDraft / sessions 这些 DSH 内部接口——
 *   粘贴走的是宿主自己的通道，插件面更小、更不容易被 DSH 升级打断。
 *   PNG 照旧存盘，仅作为剪贴板失败时的兜底。
 */
window.__ModuleLoader__.load({
  id: 'dsh-screenshot-plugin',
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' });

    function safeRequire(name) {
      try {
        return require(name);
      } catch (err) {
        console.warn('[dsh-screenshot]', 'require failed:', name, err);
        return null;
      }
    }

    // ---- 屏幕内 toast（诊断用，几秒后自动淡出）----
    let toastEl = null;
    function showToast(text, kind) {
      try {
        if (!toastEl) {
          toastEl = document.createElement('div');
          toastEl.style.cssText = 'position:fixed;left:50%;bottom:96px;transform:translateX(-50%);' +
            'padding:10px 16px;border-radius:12px;font-size:13px;line-height:20px;z-index:2147483000;' +
            'max-width:80vw;box-shadow:0 8px 30px rgba(0,0,0,.25);transition:opacity .15s ease;' +
            'pointer-events:none;white-space:pre-wrap;word-break:break-word;';
          document.body.appendChild(toastEl);
        }
        const colors = {
          info: ['rgba(42,42,42,.96)', '#e8e8e8'],
          error: ['#3a1d1d', '#ffb4b4'],
          ok: ['#12311f', '#9fe7b5'],
        }[kind] || ['rgba(42,42,42,.96)', '#e8e8e8'];
        toastEl.style.background = colors[0];
        toastEl.style.color = colors[1];
        toastEl.textContent = text;
        toastEl.style.opacity = '1';
        clearTimeout(showToast._t);
        showToast._t = setTimeout(() => { toastEl.style.opacity = '0'; }, kind === 'error' ? 9000 : 5000);
      } catch (e) { /* toast is diagnostic only */ }
    }

    function apply(ctx) {
      try {
        const react = safeRequire('react');
        if (!react) return;
        const h = react.createElement;

        function ScreenshotButton(props) {
          const [busy, setBusy] = react.useState(false);
          const onClick = async () => {
            if (busy) return;
            setBusy(true);
            try {
              const res = await fetch('/api/screenshot/capture', { method: 'POST' });
              const data = await res.json();
              if (!data.ok) {
                if (data.cancelled) { /* silent cancel */ }
                else { console.error('[dsh-screenshot]', data.error || ('HTTP ' + res.status)); showToast('截屏失败：' + (data.error || ('HTTP ' + res.status)), 'error'); }
                return;
              }
              // Deliberately do NOT touch the composer draft any more.
              // setDraft() replaced the whole draft: typed text was lost and only
              // one shot could ever be held. The image is already on the Windows
              // clipboard, so Ctrl+V uses the host's own paste path - no internal API.
              if (data.clipboard === false) {
                showToast('截图已保存，但写入剪贴板失败。请手动打开下面的文件复制图片：\n' + (data.path || data.file), 'error');
              } else {
                showToast('截图已复制到剪贴板 —— 按 Ctrl+V 粘贴进输入框即可发送\n' + data.file, 'ok');
              }
            } catch (err) {
              console.error('[dsh-screenshot]', err);
              showToast('截屏处理出错：' + (err && err.message ? err.message : err), 'error');
            } finally {
              setBusy(false);
            }
          };
          return h('button', {
            type: 'button',
            onClick,
            disabled: busy,
            title: busy ? '截屏中…（拖动框选区域）' : '一键框选截屏：截图存入工作文件夹，标记自动填入输入框',
            'aria-label': '框选截屏',
            style: {
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: '28px',
              height: '28px',
              padding: '0',
              border: 'none',
              borderRadius: '8px',
              background: 'transparent',
              color: 'var(--dsw-alias-label-tertiary, #9a9a9a)',
              cursor: busy ? 'default' : 'pointer',
              fontSize: '16px',
              lineHeight: '1',
              fontFamily: 'inherit',
              opacity: busy ? 0.5 : 1,
            },
            onMouseEnter: (e) => {
              if (!busy) {
                e.currentTarget.style.background = 'var(--dsw-alias-interactive-bg-hover, #2a2a2a)';
                e.currentTarget.style.color = 'var(--dsw-alias-label-primary, #e8e8e8)';
              }
            },
            onMouseLeave: (e) => {
              e.currentTarget.style.background = 'transparent';
              e.currentTarget.style.color = 'var(--dsw-alias-label-tertiary, #9a9a9a)';
            },
          }, busy ? '⏳' : '✂');
        }

        ctx.slots.inject('conversation.input.left', function* () {
          yield ctx.slots.register(
            { name: 'conversation.input.left', id: 'dsh-screenshot', key: 'dsh-screenshot' },
            ScreenshotButton,
          );
        });
      } catch (err) {
        console.error('[dsh-screenshot]', 'apply failed:', err);
      }
    }

    exports.apply = apply;
    exports.inject = ['slots'];
    return module.exports;
  },
});
