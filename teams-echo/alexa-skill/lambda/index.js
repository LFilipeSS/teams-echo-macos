'use strict';

function viewerURL(value) {
    const url = new URL(value);
    const octets = url.hostname.split('.').map(Number);
    const privateIPv4 = octets.length === 4 && octets.every(n => Number.isInteger(n) && n >= 0 && n <= 255) &&
        (octets[0] === 10 || (octets[0] === 192 && octets[1] === 168) ||
        (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31));
    if (!privateIPv4 || url.protocol !== 'http:' || url.port !== '3132' || url.username || url.password ||
        url.search || url.hash || !/^\/[a-f0-9]{16}\/$/.test(url.pathname)) throw new Error('INVALID_LOCAL_VIEWER');
    return url.href;
}

function speech(message) {
    return { version: '1.0', response: { outputSpeech: { type: 'PlainText', text: message }, shouldEndSession: true } };
}

function respond(event, configuredURL) {
    const type = event.request?.type;
    const intent = event.request?.intent?.name;
    if (event.context?.System?.user?.userId === 'alexa-lambda-availability' ||
        event.session?.user?.userId === 'alexa-lambda-availability') {
        return { version: '1.0', response: { shouldEndSession: true } };
    }
    if (type === 'SessionEndedRequest' || ['AMAZON.StopIntent', 'AMAZON.CancelIntent'].includes(intent)) {
        return { version: '1.0', response: { shouldEndSession: true } };
    }
    if (intent === 'AMAZON.HelpIntent') return speech('Clique em desenvolvimento no Mac para abrir o Teams nesta Echo Show.');
    if (type !== 'LaunchRequest' && intent !== 'OpenTeamsIntent') return speech('Use abrir painel de trabalho.');
    if (!event.context?.System?.device?.supportedInterfaces?.['Alexa.Presentation.APL']) {
        return speech('Abra esta skill na sua Echo Show com tela.');
    }
    let source;
    try { source = viewerURL(configuredURL); }
    catch (_) { return speech('O endereço local do Teams precisa ser configurado no Mac.'); }
    const token = 'teams-echo-viewer';
    return { version: '1.0', response: {
        directives: [{
            type: 'Alexa.Presentation.APL.RenderDocument', token,
            document: {
                type: 'APL', version: '1.4', theme: 'dark',
                mainTemplate: { items: [{ type: 'Text', id: 'status',
                    text: "${environment.allowOpenURL ? 'Abrindo Teams no Mac…' : 'Este dispositivo não permite abrir o navegador.'}",
                    width: '100%', height: '100%', textAlign: 'center', textAlignVertical: 'center' }] }
            }
        }, {
            type: 'Alexa.Presentation.APL.ExecuteCommands', token,
            commands: [{ type: 'OpenURL', when: '${environment.allowOpenURL}', source,
                onFail: [{ type: 'SetValue', componentId: 'status', property: 'text',
                    value: 'Não foi possível abrir o navegador. Verifique o Teams Echo no Mac.' }] }]
        }], shouldEndSession: false
    } };
}

exports.handler = async event => {
    let url = process.env.TEAMS_ECHO_VIEWER_URL;
    if (!url) {
        try { url = require('./viewer-config.json').url; } catch (_) { /* Not deployed yet. */ }
    }
    return respond(event, url);
};
exports.respond = respond;
exports.viewerURL = viewerURL;
