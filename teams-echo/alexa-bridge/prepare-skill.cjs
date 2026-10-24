'use strict';
process.umask(0o077);
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { directory, writePrivate } = require('./session.cjs');
const { viewerURL } = require('../alexa-skill/lambda/index.js');

function prepareSkill(config, destination, source = path.resolve(__dirname, '../alexa-skill/lambda')) {
    const url = viewerURL(config.viewerURL);
    const lambda = path.join(destination, 'skill-package', 'lambda');
    fs.mkdirSync(lambda, { recursive: true, mode: 0o700 });
    fs.chmodSync(destination, 0o700);
    fs.chmodSync(path.dirname(lambda), 0o700);
    fs.chmodSync(lambda, 0o700);
    for (const name of ['index.js', 'package.json']) {
        fs.copyFileSync(path.join(source, name), path.join(lambda, name));
        fs.chmodSync(path.join(lambda, name), 0o600);
    }
    writePrivate(path.join(lambda, 'viewer-config.json'), { url });
    const zip = path.join(destination, 'painel-de-trabalho-private.zip');
    // A new archive avoids carrying obsolete files from a previous package.
    const pending = path.join(destination, 'painel-de-trabalho-private.pending.zip');
    if (fs.existsSync(pending)) fs.unlinkSync(pending);
    execFileSync('/usr/bin/ditto', ['-c', '-k', '--keepParent', lambda, pending]);
    fs.chmodSync(pending, 0o600);
    fs.renameSync(pending, zip);
    return zip;
}
module.exports = { prepareSkill };
if (require.main === module) {
    try {
        const config = JSON.parse(fs.readFileSync(path.join(directory, 'integration.json'), 'utf8'));
        console.log(prepareSkill(config, directory));
        console.log('Importe este ZIP privado na aba Code da skill. Não publique o ZIP.');
    } catch (_) { console.error('Não foi possível preparar a skill. Execute configure.cjs e tente novamente.'); process.exitCode = 1; }
}
