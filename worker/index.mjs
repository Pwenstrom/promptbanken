const DEMO_RECORDING_PATH = '/openaimcpssubmission.mp4';
const DEMO_RECORDING_KEY = 'openaimcpssubmission.mp4';

function responseFromObject(object, includeBody) {
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('accept-ranges', 'bytes');
  headers.set('etag', object.httpEtag);

  if (object.range) {
    const end = object.range.offset + object.range.length - 1;
    headers.set('content-range', `bytes ${object.range.offset}-${end}/${object.size}`);
    return new Response(includeBody ? object.body : null, { status: 206, headers });
  }

  return new Response(includeBody ? object.body : null, { headers });
}

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);

    if (pathname !== DEMO_RECORDING_PATH) {
      return env.ASSETS.fetch(request);
    }

    if (request.method === 'HEAD') {
      const object = await env.PROMPTBANKEN_MEDIA.head(DEMO_RECORDING_KEY);
      return object === null
        ? new Response('Not Found', { status: 404 })
        : responseFromObject(object, false);
    }

    if (request.method !== 'GET') {
      return new Response('Method Not Allowed', {
        status: 405,
        headers: { Allow: 'GET, HEAD' }
      });
    }

    const object = await env.PROMPTBANKEN_MEDIA.get(DEMO_RECORDING_KEY, {
      range: request.headers
    });
    return object === null
      ? new Response('Not Found', { status: 404 })
      : responseFromObject(object, true);
  }
};
