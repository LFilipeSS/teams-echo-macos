'use strict';

// Amazon's HSTS is correct on Amazon, but must not be forwarded as a
// persistent HTTPS policy for this HTTP-only loopback login endpoint.
// This does not change certificate validation or TLS on upstream requests.
function finishLocalResponse(response, hostname, port) {
    delete response.headers['strict-transport-security'];
    const location = response.headers.location;
    if (!location) return;
    let url;
    try { url = new URL(location); } catch (_) { return; }
    if (url.hostname === hostname && url.port === String(port) && url.protocol === 'https:') {
        url.protocol = 'http:';
        response.headers.location = url.href;
    }
}

function installLoopbackAdapter(hostname, port) {
    const middleware = require('http-proxy-middleware');
    const create = middleware.createProxyMiddleware;
    middleware.createProxyMiddleware = function (context, options) {
        const original = options.onProxyRes;
        return create(context, { ...options, onProxyRes(response, request, result) {
            original?.(response, request, result);
            finishLocalResponse(response, hostname, port);
        } });
    };
}

module.exports = { finishLocalResponse, installLoopbackAdapter };
