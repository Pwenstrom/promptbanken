import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const workerModuleUrl = new URL('../worker/index.mjs', import.meta.url);

test('serves the OpenAI demo recording from R2 with byte-range support', async () => {
  assert.equal(existsSync(fileURLToPath(workerModuleUrl)), true, 'media worker is missing');

  const { default: worker } = await import(workerModuleUrl);
  let receivedKey;
  let receivedRange;
  const object = {
    body: new Uint8Array([1, 2, 3, 4]),
    size: 40,
    range: { offset: 10, length: 4 },
    httpEtag: '"demo-etag"',
    writeHttpMetadata(headers) {
      headers.set('content-type', 'video/mp4');
      headers.set('cache-control', 'public, max-age=31536000, immutable');
    }
  };
  const response = await worker.fetch(
    new Request('https://app.promptbanken.se/openaimcpssubmission.mp4', {
      headers: { Range: 'bytes=10-13' }
    }),
    {
      PROMPTBANKEN_MEDIA: {
        async get(key, options) {
          receivedKey = key;
          receivedRange = options.range.get('range');
          return object;
        }
      }
    }
  );

  assert.equal(receivedKey, 'openaimcpssubmission.mp4');
  assert.equal(receivedRange, 'bytes=10-13');
  assert.equal(response.status, 206);
  assert.equal(response.headers.get('content-type'), 'video/mp4');
  assert.equal(response.headers.get('content-range'), 'bytes 10-13/40');
  assert.equal(response.headers.get('etag'), '"demo-etag"');
});
