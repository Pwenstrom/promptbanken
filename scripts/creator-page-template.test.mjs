// scripts/creator-page-template.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { renderCreatorPage, renderCreatorIndexPage } from './creator-page-template.mjs';

const baseProfile = {
    slug: 'anna-andersson',
    display_name: 'Anna Andersson',
    bio_short: 'AI-konsult och utbildare.',
    bio_long: 'Arbetar med införande av AI i offentlig sektor.',
    competence_areas: ['Ledarskap', 'Förändringsledning'],
    organisation: 'Exempelbolaget AB',
    website_url: 'https://example.com',
    linkedin_url: 'https://linkedin.com/in/anna'
};

function render(overrides = {}) {
    return renderCreatorPage({ profile: baseProfile, indexable: true, ...overrides });
}

test('sidan har dokumentstruktur, H1 och canonical', () => {
    const html = render();
    assert.match(html, /^<!DOCTYPE html>/);
    assert.match(html, /<html lang="sv">/);
    assert.match(html, /<h1[^>]*>Anna Andersson<\/h1>/);
    assert.match(html, /<link rel="canonical" href="https:\/\/app\.promptbanken\.se\/creator\/anna-andersson\/">/);
});

test('sidan markerar tydligt att innehållet är från en creator', () => {
    assert.match(render(), /Creator på Promptbanken/);
});

test('initialer renderas i stället för avatarbild', () => {
    const html = render();
    assert.match(html, /AA/);
    assert.doesNotMatch(html, /<img/);
});

test('externa länkar har nofollow och noopener', () => {
    const html = render();
    assert.match(html, /href="https:\/\/example\.com"[^>]*rel="nofollow noopener"/);
    assert.match(html, /href="https:\/\/linkedin\.com\/in\/anna"[^>]*rel="nofollow noopener"/);
});

test('farliga länkar renderas inte alls', () => {
    const html = render({
        profile: { ...baseProfile, website_url: 'javascript:alert(1)', linkedin_url: '//evil.com' }
    });
    assert.doesNotMatch(html, /javascript:/);
    assert.doesNotMatch(html, /evil\.com/);
});

test('nollägessektioner finns för paket, prompts och krediter', () => {
    const html = render();
    assert.match(html, /Publicerade paket/);
    assert.match(html, /Publicerade prompts/);
    assert.match(html, /Workshopkrediter/);
    assert.match(html, /Inget publicerat ännu/);
});

test('icke-indexerbar profil får noindex', () => {
    assert.doesNotMatch(render(), /noindex/);
    assert.match(render({ indexable: false }), /<meta name="robots" content="noindex">/);
});

test('all profiltext escapas', () => {
    const html = render({
        profile: { ...baseProfile, display_name: '<script>alert(1)</script>', organisation: '"co" & co' }
    });
    assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
    assert.match(html, /&lt;script&gt;/);
    assert.match(html, /&quot;co&quot; &amp; co/);
});

test('JSON-LD innehåller Person och BreadcrumbList och kan inte bryta ut', () => {
    const html = render({ profile: { ...baseProfile, display_name: 'A</script><b>' } });
    assert.match(html, /"@type":\s*"Person"/);
    assert.match(html, /"@type":\s*"BreadcrumbList"/);
    assert.doesNotMatch(html, /A<\/script><b>/);
});

test('tomma valfria fält utelämnas', () => {
    const html = render({
        profile: { slug: 'x', display_name: 'X', bio_short: 'Kort' }
    });
    assert.doesNotMatch(html, /Organisation/);
    assert.doesNotMatch(html, /Kompetensområden/);
});

test('översikten listar profiler och länkar rätt', () => {
    const html = renderCreatorIndexPage({
        profiles: [{ slug: 'anna-andersson', display_name: 'Anna Andersson', bio_short: 'Konsult' }],
        indexable: true
    });
    assert.match(html, /href="\/creator\/anna-andersson\/"/);
    assert.match(html, /<link rel="canonical" href="https:\/\/app\.promptbanken\.se\/creator\/">/);
});

test('tom översikt får noindex', () => {
    const html = renderCreatorIndexPage({ profiles: [], indexable: false });
    assert.match(html, /<meta name="robots" content="noindex">/);
});
