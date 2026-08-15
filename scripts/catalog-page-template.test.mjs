// scripts/catalog-page-template.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { renderPackagePage, renderPackageIndexPage } from './catalog-page-template.mjs';

const testSupabase = { url: 'https://db.example.co', anonKey: 'anon-key-123' };

test('spårningsanropet utelämnas helt när Supabase-uppgifter saknas', () => {
    const html = renderPackagePage({
        pkg: { slug: 'x', title: 'X', summary: 'S' },
        prompts: [],
        related: [],
        indexable: true
    });
    assert.doesNotMatch(html, /track_library_usage_event/);
});

test('spårningsanropet skickar package_page_view med rätt slug', () => {
    const html = renderPackagePage({
        pkg: { slug: 'ai-for-hr', title: 'X', summary: 'S' },
        prompts: [],
        related: [],
        indexable: true,
        supabase: testSupabase
    });
    assert.match(html, /https:\/\/db\.example\.co\/rest\/v1\/rpc\/track_library_usage_event/);
    assert.match(html, /p_event_type: 'package_page_view'/);
    assert.match(html, /p_package_slug: "ai-for-hr"/);
    assert.match(html, /keepalive: true/);
});

test('spårningsanropet samlar ingen identifierare utöver paketets slug', () => {
    const html = renderPackagePage({
        pkg: { slug: 'ai-for-hr', title: 'X', summary: 'S' },
        prompts: [],
        related: [],
        indexable: true,
        supabase: testSupabase
    });
    assert.doesNotMatch(html, /document\.cookie/);
    assert.doesNotMatch(html, /localStorage/);
    assert.doesNotMatch(html, /navigator\.userAgent/);
});

const basePkg = {
    slug: 'ai-for-hr',
    title: 'AI för HR',
    summary: 'Sju arbetsflöden för HR-arbete.',
    intro_text: 'Det här paketet hjälper HR att komma igång.',
    audience_label: 'HR-specialister',
    problem_text: 'HR lägger tid på återkommande textarbete.',
    when_to_use: 'Vid rekrytering och medarbetarsamtal.',
    outcome_text: 'Färdiga underlag på minuter.',
    area: 'ledarskap',
    tags: ['hr', 'rekrytering']
};

const basePrompts = [
    { prompt_slug: 'a', title: 'Steg ett', summary: 'Sammanfattning ett', step_title: 'Förbered', step_intro: 'Börja här.' },
    { prompt_slug: 'b', title: 'Steg två', summary: 'Sammanfattning två', step_title: null, step_intro: null }
];

function render(overrides = {}) {
    return renderPackagePage({
        pkg: basePkg,
        prompts: basePrompts,
        related: [],
        indexable: true,
        ...overrides
    });
}

test('sidan har korrekt dokumentstruktur och H1', () => {
    const html = render();
    assert.match(html, /^<!DOCTYPE html>/);
    assert.match(html, /<html lang="sv">/);
    assert.match(html, /<h1[^>]*>AI för HR<\/h1>/);
});

test('metadata, canonical och OG är korrekta', () => {
    const html = render();
    assert.match(html, /<link rel="canonical" href="https:\/\/app\.promptbanken\.se\/paket\/ai-for-hr\/">/);
    assert.match(html, /<meta name="description" content="Sju arbetsflöden för HR-arbete\.">/);
    assert.match(html, /<meta property="og:url" content="https:\/\/app\.promptbanken\.se\/paket\/ai-for-hr\/">/);
    assert.match(html, /<meta property="og:title" content="AI för HR \| Promptbanken">/);
    assert.match(html, /<meta property="og:image" content="https:\/\/app\.promptbanken\.se\/brand-mark\.png">/);
});

test('indexerbar sida saknar noindex, icke-indexerbar har det', () => {
    assert.doesNotMatch(render(), /noindex/);
    assert.match(render({ indexable: false }), /<meta name="robots" content="noindex">/);
});

test('källraden anger Promptbanken', () => {
    assert.match(render(), /Av Promptbanken/);
});

test('alla redaktionella sektioner renderas när fälten är ifyllda', () => {
    const html = render();
    assert.match(html, /Vilket problem paketet löser/);
    assert.match(html, /HR lägger tid på återkommande textarbete\./);
    assert.match(html, /Vem det är för/);
    assert.match(html, /HR-specialister/);
    assert.match(html, /När det passar/);
    assert.match(html, /Vid rekrytering och medarbetarsamtal\./);
    assert.match(html, /Vad du får ut/);
    assert.match(html, /Färdiga underlag på minuter\./);
});

test('tomma redaktionella fält utelämnas helt', () => {
    const html = render({
        pkg: { ...basePkg, problem_text: null, when_to_use: '', outcome_text: undefined }
    });
    assert.doesNotMatch(html, /Vilket problem paketet löser/);
    assert.doesNotMatch(html, /När det passar/);
    assert.doesNotMatch(html, /Vad du får ut/);
    assert.match(html, /Vem det är för/);
});

test('innehållsförteckningen visar stegen i ordning med falltillbaka-titel', () => {
    const html = render();
    assert.ok(html.indexOf('Förbered') < html.indexOf('Steg två'));
    assert.match(html, /Börja här\./);
    assert.match(html, /Steg två/);
});

test('åtgärdslänken pekar på appens paketvy', () => {
    assert.match(render(), /href="\/promptbanken\.html\?package=ai-for-hr"/);
});

test('relaterade paket renderas, och sektionen utelämnas när listan är tom', () => {
    const medRelaterade = render({
        related: [{ slug: 'battre-moten', title: 'Bättre möten', summary: 'Om möten.' }]
    });
    assert.match(medRelaterade, /Relaterade paket/);
    assert.match(medRelaterade, /href="\/paket\/battre-moten\/"/);
    assert.doesNotMatch(render(), /Relaterade paket/);
});

test('taggar länkar till översiktens områdesankare', () => {
    assert.match(render(), /href="\/paket\/#omrade-ledarskap"/);
});

test('JSON-LD innehåller BreadcrumbList och ItemList men inte HowTo', () => {
    const html = render();
    assert.match(html, /"@type":\s*"BreadcrumbList"/);
    assert.match(html, /"@type":\s*"ItemList"/);
    assert.doesNotMatch(html, /HowTo/);
});

test('all databastext escapas', () => {
    const html = render({
        pkg: { ...basePkg, title: '<img src=x onerror=alert(1)>', summary: '"citat" & co' }
    });
    assert.doesNotMatch(html, /<img src=x/);
    assert.match(html, /&lt;img src=x onerror=alert\(1\)&gt;/);
    assert.match(html, /&quot;citat&quot; &amp; co/);
});

test('översiktssidan grupperar per område med ankare', () => {
    const html = renderPackageIndexPage({
        groups: [
            { area: 'ledarskap', label: 'ledarskap', packages: [{ slug: 'a', title: 'A', summary: 'Om A' }] },
            { area: null, label: 'Övriga paket', packages: [{ slug: 'b', title: 'B', summary: 'Om B' }] }
        ]
    });
    assert.match(html, /id="omrade-ledarskap"/);
    assert.match(html, /id="omrade-ovriga"/);
    assert.match(html, /Övriga paket/);
    assert.match(html, /href="\/paket\/a\/"/);
    assert.match(html, /<link rel="canonical" href="https:\/\/app\.promptbanken\.se\/paket\/">/);
});
