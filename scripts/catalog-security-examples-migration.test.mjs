import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const migrationUrl = new URL(
  '../supabase/migrations/20260802100000_catalog_security_examples.sql',
  import.meta.url,
);

test('catalog security examples migration drops every table function before changing its result columns', async () => {
  const migration = await readFile(migrationUrl, 'utf8');

  const functions = [
    ['public.list_published_prompts(text[])', 'create or replace function public.list_published_prompts('],
    ['public.get_published_prompt(text, text[])', 'create or replace function public.get_published_prompt('],
    ['app_private.get_catalog_prompt_by_id(uuid)', 'create or replace function app_private.get_catalog_prompt_by_id('],
    ['public.get_catalog_prompt_by_id(uuid)', 'create or replace function public.get_catalog_prompt_by_id('],
  ];

  for (const [signature, replacement] of functions) {
    const dropIndex = migration.indexOf(`drop function if exists ${signature};`);
    const replacementIndex = migration.indexOf(replacement);

    assert.ok(dropIndex >= 0, `the old ${signature} function must be dropped`);
    assert.ok(replacementIndex >= 0, `the replacement ${signature} function must exist`);
    assert.ok(dropIndex < replacementIndex, `the old ${signature} function must be dropped before it is replaced`);
  }
});
