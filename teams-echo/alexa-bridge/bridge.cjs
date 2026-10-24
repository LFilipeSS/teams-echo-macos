'use strict';
process.umask(0o077);
const fs = require('node:fs');
const path = require('node:path');
const { directory, writePrivate, readSession } = require('./session.cjs');

function report(state) { console.log(JSON.stringify({ state, timestamp: new Date().toISOString() })); }

async function login() {
    require('./local-proxy.cjs').installLoopbackAdapter('localhost', 3133);
    const cookie = require('alexa-cookie2');
    fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
    fs.chmodSync(directory, 0o700);
    let previous;
    try { previous = readSession(); } catch (_) { /* First connection. */ }
    report('WAITING_FOR_AMAZON_LOGIN_AT_HTTP_LOCALHOST_3133');
    cookie.generateAlexaCookie({
        amazonPage: 'amazon.com.br',
        baseAmazonPage: 'amazon.com',
        amazonPageProxyLanguage: 'pt_BR',
        acceptLanguage: 'pt-BR',
        proxyOnly: true,
        setupProxy: true,
        proxyOwnIp: 'localhost',
        proxyListenBind: '127.0.0.1',
        proxyPort: 3133,
        proxyLogLevel: 'silent',
        deviceAppName: 'Teams Echo Mac',
        formerDataStorePath: path.join(directory, 'registration.json'),
        formerRegistrationData: previous,
        logger: undefined,
        proxyCloseWindowHTML: '<!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>Teams Echo conectado</title><h1>Conexão com a Amazon concluída</h1><p>Pode fechar esta aba e voltar ao Terminal. Nenhuma senha foi salva pelo Teams Echo.</p></html>'
    }, (error, result) => {
        if (result?.localCookie && result?.refreshToken) {
            writePrivate(path.join(directory, 'session.json'), result);
            report('AMAZON_SESSION_SAVED_LOCALLY');
            cookie.stopProxyServer();
            setTimeout(() => process.exit(0), 1500);
        } else if (error) {
            // The library calls back once when it starts waiting for manual login.
            // Never print its error, cookies, login form contents or request URLs.
            if (!String(error.message).includes('Please open http://localhost:3133/')) {
                report('AMAZON_LOGIN_PENDING_OR_FAILED');
            }
        }
    });
}

async function connect() {
    const Alexa = require('alexa-remote2');
    const alexa = new Alexa();
    const session = readSession();
    alexa.on('cookie', () => {
        if (alexa.cookieData?.refreshToken) writePrivate(path.join(directory, 'session.json'), alexa.cookieData);
    });
    await new Promise((resolve, reject) => alexa.init({
        cookie: session,
        formerRegistrationData: session,
        amazonPage: 'amazon.com.br',
        alexaServiceHost: 'alexa.amazon.com.br',
        acceptLanguage: 'pt-BR',
        setupProxy: false,
        useWsMqtt: false,
        bluetooth: false,
        cookieRefreshInterval: 0,
        formerDataStorePath: path.join(directory, 'registration.json'),
        logger: undefined
    }, error => error ? reject(new Error('AMAZON_CONNECTION_FAILED')) : resolve()));
    return alexa;
}

async function main() {
    const mode = process.argv[2];
    if (mode === 'login') return login();
    if (!['devices', 'command', 'skill'].includes(mode)) throw new Error('USE_LOGIN_DEVICES_COMMAND_OR_SKILL');
    const device = process.argv[3];
    const command = process.argv[4];
    if (mode !== 'devices' && (!device || !command)) throw new Error('DEVICE_AND_COMMAND_REQUIRED');
    if (mode === 'skill' && !/^amzn1\.ask\.skill\.[0-9a-f-]{36}$/i.test(command)) throw new Error('INVALID_SKILL_ID');
    const timer = setTimeout(() => { report('AMAZON_REQUEST_TIMEOUT'); process.exit(1); }, 45000);
    const alexa = await connect();
    try {
        if (mode === 'devices') {
            // Only the fields needed to select the target. No account, history or contacts.
            console.log(JSON.stringify(Object.values(alexa.serialNumbers).map(device => ({
                name: device.accountName, serial: device.serialNumber,
                family: device.deviceFamily, type: device.deviceType, online: device.online
            }))));
        } else {
            await new Promise((resolve, reject) => alexa.sendSequenceCommand(device, mode === 'skill' ? 'skill' : 'textCommand', command,
                error => error ? reject(new Error('AMAZON_COMMAND_REJECTED')) : resolve()));
            report('COMMAND_ACCEPTED_BY_AMAZON_NOT_YET_VERIFIED_ON_ECHO');
        }
    } finally { clearTimeout(timer); alexa.stop(); }
}

main().catch(error => {
    const allowed = ['AUTH_REQUIRED', 'USE_LOGIN_DEVICES_COMMAND_OR_SKILL', 'DEVICE_AND_COMMAND_REQUIRED', 'INVALID_SKILL_ID',
        'AMAZON_CONNECTION_FAILED', 'AMAZON_COMMAND_REJECTED'];
    report(allowed.includes(error.message) ? error.message : 'BRIDGE_FAILED');
    process.exit(1);
});
