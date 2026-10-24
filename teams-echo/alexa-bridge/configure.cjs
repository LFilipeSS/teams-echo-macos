'use strict';
process.umask(0o077);
const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline/promises');
const { directory, writePrivate } = require('./session.cjs');
const { viewerURL } = require('../alexa-skill/lambda/index.js');

function configuration({ url, device, deviceName, skillId }, node = process.execPath) {
    const normalizedURL = viewerURL(url.trim());
    if (!/^[A-Za-z0-9_-]{4,100}$/.test(device.trim())) throw new Error('Serial do dispositivo inválido.');
    if (!/^amzn1\.ask\.skill\.[a-f0-9-]{36}$/i.test(skillId.trim())) throw new Error('Skill ID inválido.');
    return { enabled: true, viewerURL: normalizedURL, device: device.trim(),
        deviceName: deviceName.trim() || 'Echo Show', skillId: skillId.trim(), node };
}
async function main() {
    const destination = path.join(directory, 'integration.json');
    const prompt = readline.createInterface({ input: process.stdin, output: process.stdout });
    try {
        if (fs.existsSync(destination)) {
            const answer = await prompt.question('Substituir a configuração Alexa existente? Digite SIM: ');
            if (answer !== 'SIM') { console.log('Configuração preservada.'); return; }
        }
        const config = configuration({
            url: await prompt.question('Endereço copiado do Teams Echo: '),
            device: await prompt.question('Serial da Echo, listado por devices: '),
            deviceName: await prompt.question('Nome da Echo: '),
            skillId: await prompt.question('Skill ID completo (amzn1.ask.skill.…): ')
        });
        writePrivate(destination, config);
        console.log('Configuração salva fora do repositório, com acesso restrito ao seu usuário.');
    } finally { prompt.close(); }
}
module.exports = { configuration };
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
