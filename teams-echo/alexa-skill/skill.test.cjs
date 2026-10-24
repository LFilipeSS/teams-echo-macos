'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { respond } = require('./lambda/index.js');
const url = 'http://192.168.50.10:3132/0123456789abcdef/';
const event = { request: { type: 'LaunchRequest' }, context: { System: { device: { supportedInterfaces: { 'Alexa.Presentation.APL': {} } } } } };

test('launch opens configured local URL without sending any image to the skill', () => {
    const result = respond(event, url);
    assert.equal(result.response.directives[1].commands[0].source, url);
    assert.equal(result.response.directives[0].token, result.response.directives[1].token);
    assert.equal(result.response.directives[1].commands[0].type, 'OpenURL');
    assert.equal(JSON.stringify(result).includes('frame.jpg'), false);
});
test('audio-only devices and availability checks receive no browser command', () => {
    assert.equal(respond({ request: { type: 'LaunchRequest' } }, url).response.directives, undefined);
    assert.equal(respond({ ...event, session: { user: { userId: 'alexa-lambda-availability' } } }, url).response.directives, undefined);
});
test('invalid destinations never get sent to the Echo', () => {
    for (const source of ['https://example.com/', 'http://127.0.0.1:3132/0123456789abcdef/',
        'http://192.168.50.10:3132/0123456789abcdef/?url=https://example.com',
        'http://user:pass@192.168.50.10:3132/0123456789abcdef/', '']) {
        const result = respond(event, source);
        assert.equal(result.response.directives, undefined);
        assert.equal(JSON.stringify(result).includes(source), source.length === 0);
    }
});
test('stop closes session without reopening the browser', () => {
    const result = respond({ ...event, request: { type: 'IntentRequest', intent: { name: 'AMAZON.StopIntent' } } }, url);
    assert.equal(result.response.shouldEndSession, true);
    assert.equal(result.response.directives, undefined);
});
