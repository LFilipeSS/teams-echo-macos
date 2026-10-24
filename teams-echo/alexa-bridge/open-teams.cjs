'use strict';
process.umask(0o077);
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync, spawn } = require('node:child_process');
const { directory } = require('./session.cjs');

async function main() {
    const config = JSON.parse(fs.readFileSync(path.join(directory, 'integration.json'), 'utf8'));
    const token = execFileSync('/usr/bin/defaults', ['read', 'br.com.luizfilipe.teams-echo', 'ViewerToken'], { encoding: 'utf8' }).trim();
    const ip = execFileSync('/usr/sbin/ipconfig', ['getifaddr', 'en0'], { encoding: 'utf8' }).trim();
    if (!/^[a-f0-9]{16}$/.test(token) || config.viewerURL !== `http://${ip}:3132/${token}/`) {
        throw new Error('VIEWER_ADDRESS_CHANGED');
    }
    let ready = false;
    for (let attempt = 0; attempt < 40; attempt++) {
        try {
            const response = await fetch(`http://127.0.0.1:3132/${token}/status.json`, { signal: AbortSignal.timeout(1000) });
            const state = await response.json();
            if (response.ok && state.ready && state.frames > 0) { ready = true; break; }
        } catch (_) { /* Native app may still be opening Teams. */ }
        await new Promise(resolve => setTimeout(resolve, 500));
    }
    if (!ready) throw new Error('TEAMS_STREAM_NOT_READY');
    if (process.argv[2] === '--check') {
        console.log(JSON.stringify({ state: 'TEAMS_STREAM_READY', skillConfigured: !!config.skillId }));
        return;
    }
    const worker = spawn(process.execPath, [path.join(__dirname, 'bridge.cjs'), 'skill', config.device, config.skillId], {
        stdio: ['ignore', 'pipe', 'ignore']
    });
    let output = '';
    worker.stdout.on('data', data => { if (output.length < 8192) output += data; });
    const timer = setTimeout(() => worker.kill('SIGTERM'), 50000);
    const code = await new Promise((resolve, reject) => {
        worker.on('error', () => reject(new Error('ALEXA_WORKER_START_FAILED')));
        worker.on('exit', code => resolve(code));
    });
    clearTimeout(timer);
    if (code !== 0 || !output.includes('COMMAND_ACCEPTED_BY_AMAZON_NOT_YET_VERIFIED_ON_ECHO')) throw new Error('ALEXA_LAUNCH_FAILED');
    console.log(JSON.stringify({ state: 'ALEXA_OPEN_REQUEST_SENT', device: config.deviceName }));
}

main().catch(error => {
    const allowed = ['VIEWER_ADDRESS_CHANGED', 'TEAMS_STREAM_NOT_READY', 'ALEXA_WORKER_START_FAILED', 'ALEXA_LAUNCH_FAILED'];
    console.log(JSON.stringify({ state: allowed.includes(error.message) ? error.message : 'ALEXA_NOT_CONFIGURED' }));
    process.exit(1);
});
