import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const pages = ['creator.html', 'creator-content.html', 'creator-packages.html', 'creator-shares.html'];
const expectedNav = ['Mitt bibliotek', 'Prompts', 'Paket', 'Delat', 'Utforska Open'];

for (const page of pages) {
    test(`${page} har bibliotekets gemensamma navigation`, () => {
        const html = readFileSync(new URL(`../${page}`, import.meta.url), 'utf8');
        const nav = html.match(/<nav>([\s\S]*?)<\/nav>/)?.[1] || '';
        for (const label of expectedNav) assert.match(nav, new RegExp(`>${label}<`));
        assert.doesNotMatch(nav, />Granskning</);
    });
}

test('promptens primära handling är Använd och Open ligger separat', () => {
    const html = readFileSync(new URL('../creator-content.html', import.meta.url), 'utf8');
    assert.match(html, /data-row-use-link[^>]*>Använd</);
    assert.match(html, /<summary>Publicera i Promptbanken Open<\/summary>/);
});
