// ohc-gw.mjs —— 把 DeepSeek 包装成标准 OpenAI 兼容端点，供宿主机 VS Code 使用
//
// 为什么需要它：目标场景是「PC 不能上网」。PC 唯一能走的通道是 USB 上的 hdc，
// 所以由手机（容器里）去连 api.deepseek.com，再把结果原样吐给 PC。
//
//   VS Code(Continue/Cline)  ──http──▶ 127.0.0.1:18080
//                                          │  hdc fport（USB 转发）
//                                          ▼
//                                    容器内 ohc-gw   ──https──▶ api.deepseek.com
//
// 接口：把 /v1/* 原样转发到 https://api.deepseek.com/v1/*
//       Authorization 由网关注入（Key 从容器 env 的 ANTHROPIC_AUTH_TOKEN 读，
//       所以 VS Code 里 API Key 随便填一个非空字符串即可）
// 流式：上游 SSE 直接 pipe 回来，不做缓冲，VS Code 里能逐字出

import http from 'node:http';
import https from 'node:https';

const KEY = process.env.ANTHROPIC_AUTH_TOKEN || '';
const PORT = Number(process.env.OHC_GW_PORT || 18080);
const UPSTREAM = process.env.OHC_GW_UPSTREAM || 'https://api.deepseek.com';

// deepseek-flash 是推理模型：思考过程也算在 max_tokens 里。
// VS Code 插件常常把 max_tokens 设得很小（64/128），结果 token 全花在思考上，
// 返回的 content 是空字符串，界面上表现为「模型不回话」。
// 所以这里给一个下限，实测 64 时 content 为空、800 时正常。
const MIN_MAXTOKENS = Number(process.env.OHC_GW_MIN_MAXTOKENS || 2048);

if (!KEY.startsWith('sk-')) {
    console.error('[ohc-gw] 没读到 ANTHROPIC_AUTH_TOKEN，检查 /data/ohc/containers/claude/env');
    process.exit(1);
}

function json(res, code, obj) {
    const s = JSON.stringify(obj);
    res.writeHead(code, { 'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(s) });
    res.end(s);
}

// DeepSeek 上游返回的 content-type 常常只有 "application/json"，不带 charset。
// PowerShell 5.1 的 Invoke-RestMethod 遇到没有 charset 的响应会按 Latin-1 解码，
// 中文全变成 "æ¶å°" 这种乱码（"收到" 的 UTF-8 字节被当成单字节字符）。
// VS Code 的插件走 Node fetch，不受影响，但 PC 侧自检脚本会被坑。
// 所以这里统一补上 charset=utf-8。
function withCharset(ct, fallback) {
    const v = ct || fallback;
    if (/charset=/i.test(v)) return v;
    if (/^(application\/json|text\/|application\/x-ndjson)/i.test(v)) return v + '; charset=utf-8';
    return v;
}

const server = http.createServer((req, res) => {
    const t0 = Date.now();

    // 每个请求打一行，写进 /work/ohc-gw.log。
    // 排查「VS Code 到底有没有打到网关上」时看这里最快。
    let finished = false;
    res.on('finish', () => {
        finished = true;
        console.log(`${new Date().toISOString()} ${req.method} ${req.url} -> ${res.statusCode} ${Date.now() - t0}ms`);
    });
    // 客户端提前断开（Continue 解析失败后主动掐断就是这种表现）
    res.on('close', () => {
        if (!finished) {
            console.log(`${new Date().toISOString()} ${req.method} ${req.url} -> CLIENT ABORTED after ${Date.now() - t0}ms`);
        }
    });

    // 健康检查：PC 侧用来确认通道通了
    if (req.url === '/healthz') {
        res.writeHead(200, { 'content-type': 'text/plain' });
        res.end('ohc-gw ok');
        return;
    }

    if (!req.url.startsWith('/v1/')) {
        json(res, 404, { error: { message: 'only /v1/* is proxied' } });
        return;
    }

    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
        let body = Buffer.concat(chunks);

        // 把过小的 max_tokens 抬到下限，避免「思考完就没额度了、content 为空」
        if (req.method === 'POST' && req.url.startsWith('/v1/chat/completions') && body.length) {
            try {
                const obj = JSON.parse(body.toString('utf8'));
                // 打一行请求摘要，出问题时能看出客户端到底发了什么
                const nMsg = Array.isArray(obj.messages) ? obj.messages.length : 0;
                const nTool = Array.isArray(obj.tools) ? obj.tools.length : 0;
                const nChar = Array.isArray(obj.messages)
                    ? obj.messages.reduce((s, m) => s + String(m.content || '').length, 0) : 0;
                console.log(`${new Date().toISOString()}   req model=${obj.model} stream=${!!obj.stream} ` +
                    `msgs=${nMsg} chars=${nChar} tools=${nTool} max_tokens=${obj.max_tokens}` +
                    (obj.tool_choice ? ` tool_choice=${JSON.stringify(obj.tool_choice)}` : ''));

                if (typeof obj.max_tokens === 'number' && obj.max_tokens < MIN_MAXTOKENS) {
                    obj.max_tokens = MIN_MAXTOKENS;
                    body = Buffer.from(JSON.stringify(obj), 'utf8');
                }
            } catch { /* 不是合法 JSON 就原样转发 */ }
        }

        const u = new URL(UPSTREAM + req.url);

        const headers = {
            'content-type': req.headers['content-type'] || 'application/json',
            'accept': req.headers['accept'] || 'application/json',
            'authorization': 'Bearer ' + KEY,
            'content-length': body.length
        };

        const up = https.request(
            { hostname: u.hostname, port: 443, path: u.pathname + u.search, method: req.method, headers },
            (ur) => {
                const status = ur.statusCode || 502;
                if (status >= 400) {
                    // 上游报错时把响应体也记下来，否则只有一个状态码根本查不出原因
                    const eb = [];
                    ur.on('data', (c) => eb.push(c));
                    ur.on('end', () => {
                        const txt = Buffer.concat(eb).toString('utf8').slice(0, 600);
                        console.log(`${new Date().toISOString()}   UPSTREAM ${status}: ${txt}`);
                        res.writeHead(status, { 'content-type': withCharset(ur.headers['content-type'], 'application/json') });
                        res.end(Buffer.concat(eb));
                    });
                    return;
                }
                res.writeHead(status, {
                    'content-type': withCharset(ur.headers['content-type'], 'application/json'),
                    'cache-control': 'no-cache',
                    // 让中间层别攒着，SSE 才能逐字到
                    'x-accel-buffering': 'no'
                });
                ur.pipe(res);
            }
        );

        up.on('error', (e) => {
            if (!res.headersSent) json(res, 502, { error: { message: 'upstream: ' + e.message } });
            else res.end();
        });

        up.write(body);
        up.end();
    });
});

server.on('error', (e) => {
    console.error('[ohc-gw] ' + e.message);
    process.exit(1);
});

server.listen(PORT, '0.0.0.0', () => {
    console.log('[ohc-gw] listening on 0.0.0.0:' + PORT + ' -> ' + UPSTREAM);
});
