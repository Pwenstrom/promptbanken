import test from 'node:test';
import assert from 'node:assert/strict';
import {
    isSafeSlug,
    escapeHtml,
    isIndexable,
    buildSitemap,
    packageUrl,
    absoluteUrl,
    groupPackagesByArea,
    areaAnchor
} from './catalog-page-lib.mjs';

test('isSafeSlug accepterar normala slugs', () => {
    assert.equal(isSafeSlug('ai-for-hr'), true);
    assert.equal(isSafeSlug('paket1'), true);
});

test('isSafeSlug avvisar sökvägsmanipulation och skräp', () => {
    assert.equal(isSafeSlug('../../etc/passwd'), false);
    assert.equal(isSafeSlug('a/b'), false);
    assert.equal(isSafeSlug('AI-FOR-HR'), false);
    assert.equal(isSafeSlug('-leading'), false);
    assert.equal(isSafeSlug('trailing-'), false);
    assert.equal(isSafeSlug(''), false);
    assert.equal(isSafeSlug(null), false);
    assert.equal(isSafeSlug(undefined), false);
});

test('escapeHtml neutraliserar taggar och attribut', () => {
    assert.equal(
        escapeHtml('<script>alert("x")</script>'),
        '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;'
    );
    assert.equal(escapeHtml("O'Brien & co"), 'O&#39;Brien &amp; co');
});

test('escapeHtml hanterar tomma värden', () => {
    assert.equal(escapeHtml(null), '');
    assert.equal(escapeHtml(undefined), '');
    assert.equal(escapeHtml(0), '0');
});

test('isIndexable kräver intro_text och minst tre prompts', () => {
    assert.equal(isIndexable({ intro_text: 'En text' }, 3), true);
    assert.equal(isIndexable({ intro_text: 'En text' }, 2), false);
    assert.equal(isIndexable({ intro_text: '' }, 5), false);
    assert.equal(isIndexable({ intro_text: null }, 5), false);
    assert.equal(isIndexable({ intro_text: '   ' }, 5), false);
});

test('is_indexable åsidosätter tröskeln i båda riktningarna', () => {
    assert.equal(isIndexable({ intro_text: '', is_indexable: true }, 0), true);
    assert.equal(isIndexable({ intro_text: 'En text', is_indexable: false }, 9), false);
    assert.equal(isIndexable({ intro_text: 'En text', is_indexable: null }, 3), true);
});

test('packageUrl och absoluteUrl bygger rätt adresser', () => {
    assert.equal(packageUrl('ai-for-hr'), '/paket/ai-for-hr/');
    assert.equal(absoluteUrl('/paket/ai-for-hr/'), 'https://app.promptbanken.se/paket/ai-for-hr/');
});

test('buildSitemap ger giltig XML med alla URL:er', () => {
    const xml = buildSitemap(['https://app.promptbanken.se/', 'https://app.promptbanken.se/paket/x/']);
    assert.match(xml, /^<\?xml version="1\.0" encoding="UTF-8"\?>/);
    assert.match(xml, /<urlset xmlns="http:\/\/www\.sitemaps\.org\/schemas\/sitemap\/0\.9">/);
    assert.match(xml, /<url><loc>https:\/\/app\.promptbanken\.se\/<\/loc><\/url>/);
    assert.match(xml, /<url><loc>https:\/\/app\.promptbanken\.se\/paket\/x\/<\/loc><\/url>/);
    assert.match(xml, /<\/urlset>\s*$/);
});

test('buildSitemap dedupar och bevarar ordning', () => {
    const xml = buildSitemap(['https://a/', 'https://b/', 'https://a/']);
    assert.equal(xml.match(/<loc>https:\/\/a\/<\/loc>/g).length, 1);
    assert.ok(xml.indexOf('https://a/') < xml.indexOf('https://b/'));
});

test('groupPackagesByArea grupperar och lägger områdeslösa sist', () => {
    const grupper = groupPackagesByArea([
        { slug: 'a', area: 'ledarskap' },
        { slug: 'b', area: null },
        { slug: 'c', area: 'ledarskap' },
        { slug: 'd', area: 'kommunikation' }
    ]);
    assert.equal(grupper.at(-1).area, null);
    assert.equal(grupper.at(-1).label, 'Övriga paket');
    assert.equal(grupper.at(-1).packages.length, 1);
    const ledarskap = grupper.find((g) => g.area === 'ledarskap');
    assert.equal(ledarskap.packages.length, 2);
});

test('areaAnchor ger stabila ankare', () => {
    assert.equal(areaAnchor('ledarskap'), 'omrade-ledarskap');
    assert.equal(areaAnchor(null), 'omrade-ovriga');
});

test('areaAnchor slugifierar fritext med mellanslag och svenska tecken', () => {
    assert.equal(areaAnchor('Vård och omsorg'), 'omrade-vard-och-omsorg');
});

test('areaAnchor normaliserar skiftläge så samma område delar ankare', () => {
    assert.equal(areaAnchor('Ledarskap'), areaAnchor('ledarskap'));
    assert.equal(areaAnchor('LEDARSKAP'), 'omrade-ledarskap');
});

test('areaAnchor trimmar kvarvarande skiljetecken', () => {
    assert.equal(areaAnchor('Ekonomi!'), 'omrade-ekonomi');
    assert.equal(areaAnchor('  HR & Rekrytering  '), 'omrade-hr-rekrytering');
});
