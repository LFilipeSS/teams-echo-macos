'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { writePrivate } = require('./session.cjs');
const { finishLocalResponse } = require('./local-proxy.cjs');

test('loopback response keeps Amazon HTTPS destinations intact', () => {
    const remote = { headers: { location: 'https://www.amazon.com/ap/signin', 'strict-transport-security': 'max-age=300' } };
    finishLocalResponse(remote, 'localhost', 3133);
    assert.equal(remote.headers.location, 'https://www.amazon.com/ap/signin');
    assert.equal(remote.headers['strict-transport-security'], undefined);
    const local = { headers: { location: 'https://localhost:3133/www.amazon.com/ap/signin' } };
    finishLocalResponse(local, 'localhost', 3133);
    assert.equal(local.headers.location, 'http://localhost:3133/www.amazon.com/ap/signin');
});

test('session replacement stays private even with permissive umask', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'teams-echo-session-test-'));
    const file = path.join(root, 'Alexa', 'session.json');
    const oldMask = process.umask(0);
    try {
        writePrivate(file, { fixture: 'first' });
        fs.chmodSync(file, 0o644);
        writePrivate(file, { fixture: 'second' });
        assert.equal(fs.statSync(file).mode & 0o777, 0o600);
        assert.equal(fs.statSync(path.dirname(file)).mode & 0o777, 0o700);
        assert.deepEqual(JSON.parse(fs.readFileSync(file)), { fixture: 'second' });
        assert.equal(fs.existsSync(file + '.pending'), false);
    } finally { process.umask(oldMask); fs.rmSync(root, { recursive: true }); }
});

test('unconfigured bridge requires login without printing session contents', () => {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'teams-echo-empty-home-'));
    try {
        const result = spawnSync(process.execPath, [path.join(__dirname, 'bridge.cjs'), 'devices'], {
            env: { ...process.env, HOME: home }, encoding: 'utf8', timeout: 10000
        });
        assert.equal(result.status, 1);
        assert.equal(JSON.parse(result.stdout).state, 'AUTH_REQUIRED');
        assert.equal(result.stderr, '');
    } finally { fs.rmSync(home, { recursive: true }); }
});
