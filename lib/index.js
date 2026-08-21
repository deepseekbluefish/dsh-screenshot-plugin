/**
 * dsh-screenshot-plugin — host 半段
 *
 * 注册 HTTP 路由 POST /api/screenshot/capture：
 * 浏览器客户端点击输入框旁的截屏按钮后调用，宿主进程拉起 PowerShell
 * 全屏框选覆盖层，用户拖框选区，松开后 PNG 存入工作文件夹（自动编号），
 * 返回 { ok, file, marker }。Esc 取消返回 { ok: false, cancelled: true }。
 */
import { spawn } from 'node:child_process';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const CAPTURE_PS1 = join(here, 'capture.ps1');
const DEFAULT_FOLDER = join(homedir(), 'Pictures', 'DSH-Screenshots');

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
  });
  res.end(body);
}

/** 拉起框选截屏脚本并收集其 JSON 输出。 */
function runCapture(folder) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', CAPTURE_PS1, '-Folder', String(folder)],
      { windowsHide: true },
    );
    let out = '';
    let err = '';
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { err += d; });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) {
        try {
          resolve(JSON.parse(out.trim()));
        } catch {
          reject(new Error(`截屏脚本输出解析失败: ${out.slice(0, 200)}`));
        }
      } else {
        reject(new Error(`截屏失败 (exit ${code}): ${(err || out).slice(0, 300)}`));
      }
    });
  });
}

export function apply(ctx, config) {
  const folder = (config && config.folder) || DEFAULT_FOLDER;

  ctx.inject(['webServer'], (scope) => {
    scope.effect(() => {
      const dispose = scope.webServer.register({
        kind: 'exact',
        path: '/api/screenshot/capture',
        handler: async (req, res) => {
          if (req.method !== 'POST') {
            sendJson(res, 405, { ok: false, error: 'method not allowed' });
            return;
          }
          try {
            const result = await runCapture(folder);
            sendJson(res, 200, result);
          } catch (err) {
            sendJson(res, 500, { ok: false, error: String(err && err.message ? err.message : err) });
          }
        },
      });
      return () => dispose();
    }, 'dsh-screenshot: http route');
  });
}

export const inject = [];
export const name = 'screenshot';
