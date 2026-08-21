/**
 * dsh-screenshot-plugin — 客户端半段
 *
 * 在对话输入框左侧注入一个截屏小按钮：
 * 点击 → POST /api/screenshot/capture（宿主拉起全屏框选截屏）
 *      → 成功后把标记【截屏N HH:mm】写入当前会话的输入框草稿
 *      → 用户点发送，agent 即可按标记读取工作文件夹里的截图。
 *
 * 填入草稿的路径（按优先级）：
 *   1. 组件 props.inputActions（会话级 slot 注入的 provide-channel props）
 *   2. ctx.sessions.provideInfo(currentId).props.inputActions
 *   3. 兜底：binding.session.prompt(..., 'queue') 直接入队消息
 * 所有步骤带屏幕内 toast 反馈，便于现场诊断；任何异常不影响应用启动。
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

    function currentSessionId(ctx) {
      try {
        const sessions = ctx.sessions;
        return sessions && sessions.list && sessions.list.getSnapshot().current;
      } catch (err) {
        console.warn('[dsh-screenshot]', 'currentSessionId failed:', err);
        return undefined;
      }
    }

    function resolveInputActions(ctx, props) {
      const tries = [];
      if (props && props.inputActions && typeof props.inputActions.setDraft === 'function') {
        tries.push('props.inputActions');
        return { actions: props.inputActions, via: 'props.inputActions', tries };
      }
      const sessions = ctx.sessions;
      const currentId = currentSessionId(ctx);
      if (currentId && sessions && typeof sessions.provideInfo === 'function') {
        try {
          const info = sessions.provideInfo(currentId);
          const actions = info && info.props && info.props.inputActions;
          tries.push('provideInfo=' + (info ? 'bundle' : 'undefined'));
          if (actions && typeof actions.setDraft === 'function') {
            return { actions, via: 'sessions.provideInfo', tries };
          }
          tries.push('provideInfo.props.inputActions missing, keys=' + (info && info.props ? Object.keys(info.props).join(',') : 'none'));
        } catch (err) {
          tries.push('provideInfo threw: ' + (err && err.message));
          console.warn('[dsh-screenshot]', 'provideInfo failed:', err);
        }
      } else {
        tries.push('no provideInfo api');
      }
      return { actions: null, via: null, tries };
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
              showToast('截屏已保存：' + data.file, 'info');
              const resolved = resolveInputActions(ctx, props);
              if (resolved.actions) {
                resolved.actions.setDraft(data.marker);
                showToast('已填入输入框：' + data.marker + '\n（via ' + resolved.via + '）', 'ok');
                return;
              }
              const currentId = currentSessionId(ctx);
              const binding = currentId && ctx.sessions.binding ? ctx.sessions.binding(currentId) : null;
              if (binding && binding.session) {
                await binding.session.prompt([{ type: 'text', text: data.marker }], 'queue');
                showToast('已作为消息入队：' + data.marker, 'ok');
                return;
              }
              const detail = resolved.tries.join(' | ') || 'unknown';
              console.error('[dsh-screenshot]', 'no draft path; tries:', detail);
              showToast('无法填入输入框，诊断：' + detail, 'error');
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
    exports.inject = ['slots', 'sessions'];
    return module.exports;
  },
});
