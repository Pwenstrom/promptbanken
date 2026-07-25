import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

import {
  buildParameterizedCatalogMigration,
  loadParameterizedPromptSeeds,
  sqlDollarQuote,
} from './generate-catalog-parameterized-prompts.mjs';

const repoRoot = fileURLToPath(new URL('..', import.meta.url));
const expectedSlugs = [
  'klarsprak',
  'mejl',
  'faq',
  'kallelse',
  'beslutsunderlag',
  'rutin',
  'tvaversioner',
  'informationsutskick',
  'enkel_infografik',
  'illustration_informationsutskick',
];

test('loads exactly the ten parameterized prompts and their package mappings', async () => {
  const seeds = await loadParameterizedPromptSeeds(repoRoot);

  assert.deepEqual(seeds.map((seed) => seed.slug), expectedSlugs);
  assert.deepEqual(
    Object.fromEntries(seeds.map((seed) => [seed.slug, seed.packageSlug])),
    {
      klarsprak: 'kommunikation',
      mejl: 'kommunikation',
      faq: 'kommunikation',
      kallelse: 'kommunikation',
      beslutsunderlag: 'beslutsberedning',
      rutin: 'processer',
      tvaversioner: 'kommunikation',
      informationsutskick: 'kommunikation',
      enkel_infografik: 'visuellt',
      illustration_informationsutskick: 'visuellt',
    },
  );

  for (const seed of seeds) {
    assert.ok(
      /\{\{[a-z_]+\}\}/.test(seed.promptText)
      || seed.parameterSchema.legacy_fallback_field,
    );
    assert.equal(seed.parameterSchema.version, 1);
    assert.ok(seed.parameterSchema.fields.length >= 3);
  }
});

test('dollar quotes text even when the preferred delimiter occurs in the value', () => {
  const quoted = sqlDollarQuote('text $prompt$ and apostrophe', 'prompt');

  assert.equal(quoted, '$prompt_1$text $prompt$ and apostrophe$prompt_1$');
});

test('keeps fallback dollar quote tags valid when the preferred tag starts with a digit', () => {
  const quoted = sqlDollarQuote('text $text_123$', '123');

  assert.equal(quoted, '$text_123_1$text $text_123$$text_123_1$');
});

test('builds an idempotent catalog migration from the real prompt sources', async () => {
  const seeds = await loadParameterizedPromptSeeds(repoRoot);
  const sql = buildParameterizedCatalogMigration(seeds);

  assert.match(sql, /insert into public\.catalog_prompts/);
  assert.match(sql, /insert into public\.catalog_prompt_variants/);
  assert.match(sql, /insert into public\.catalog_package_items/);
  assert.equal((sql.match(/on conflict/gi) || []).length, 3);
  assert.equal((sql.match(/\('(?:klarsprak|mejl|faq|kallelse|beslutsunderlag|rutin|tvaversioner|informationsutskick|enkel_infografik|illustration_informationsutskick)'/g) || []).length, 10);

  const mejlText = await readFile(new URL('../prompts/mejl.txt', import.meta.url), 'utf8');
  assert.ok(sql.includes(mejlText.trim()));
  assert.match(sql, /raise exception 'Katalogpaket saknas: %'/);
  assert.match(
    sql,
    /from parameterized_catalog_prompt_seed\s+on conflict \(slug\) do nothing;/,
  );
  assert.match(sql, /do update set\s+prompt_text = excluded\.prompt_text/);
  assert.match(sql, /do update set\s+sort_order = excluded\.sort_order/);
});
