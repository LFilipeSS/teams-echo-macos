'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { configuration } = require('./configure.cjs');
const { prepareSkill } = require('./prepare-skill.cjs');
const input = { url: 'http://192.168.50.10:3132/0123456789abcdef/', device: 'EXAMPLE1234',
    deviceName: 'Echo de teste', skillId: 'amzn1.ask.skill.00000000-0000-0000-0000-000000000000' };
test('configuração valida endereço local e identificadores sem usar a conta real', () => {
    const config = configuration(input, '/example/node');
    assert.equal(config.node, '/example/node');
    assert.equal(config.enabled, true);
    assert.throws(() => configuration({ ...input, url: 'https://example.com/' }));
    assert.throws(() => configuration({ ...input, device: '../invalid' }));
    assert.throws(() => configuration({ ...input, skillId: 'invalid' }));
});
test('ZIP contém lambda e configuração privada, com permissões restritas', t => {
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'teams-echo-setup-'));
    t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
    const zip = prepareSkill(configuration(input), temp);
    assert.equal(fs.statSync(zip).mode & 0o777, 0o600);
    assert.equal(fs.statSync(temp).mode & 0o777, 0o700);
    const names = execFileSync('/usr/bin/unzip', ['-Z1', zip], { encoding: 'utf8' });
    for (const name of ['lambda/index.js', 'lambda/package.json', 'lambda/viewer-config.json']) assert.ok(names.includes(name));
    const config = JSON.parse(execFileSync('/usr/bin/unzip', ['-p', zip, 'lambda/viewer-config.json'], { encoding: 'utf8' }));
    assert.equal(config.url, input.url);
    assert.ok(!names.includes('session.json'));
});
