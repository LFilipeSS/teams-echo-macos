'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const directory = path.join(os.homedir(), 'Library', 'Application Support', 'TeamsEcho', 'Alexa');

function writePrivate(file, value) {
    fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
    fs.chmodSync(path.dirname(file), 0o700);
    const temporary = file + '.pending';
    fs.writeFileSync(temporary, JSON.stringify(value), { mode: 0o600, flag: 'w' });
    fs.chmodSync(temporary, 0o600);
    fs.renameSync(temporary, file);
}

function readSession() {
    const file = path.join(directory, 'session.json');
    if (!fs.existsSync(file)) throw new Error('AUTH_REQUIRED');
    fs.chmodSync(file, 0o600);
    return JSON.parse(fs.readFileSync(file, 'utf8'));
}

module.exports = { directory, writePrivate, readSession };
