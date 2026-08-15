// scripts/catalog-page-template.mjs
// HTML-mallar för statiska katalogsidor. Återanvänder style.css och samma
// head-mönster som övriga sidor, så sidorna ärver designsystemet.

import { escapeHtml, packageUrl, absoluteUrl, areaAnchor } from './catalog-page-lib.mjs';

function hasText(value) {
    return typeof value === 'string' && value.trim() !== '';
}

function head({ title, description, canonicalPath, indexable }) {
    const safeTitle = hasText(title) ? title : null;
    const safeDescription = hasText(description) ? description : '';
    const fullTitle = safeTitle ? `${safeTitle} | Promptbanken` : 'Promptbanken';
    return `<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${escapeHtml(fullTitle)}</title>
    <link rel="icon" href="/favicon.ico" sizes="any">
    <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
    <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
    <link rel="apple-touch-icon" href="/apple-touch-icon.png">
    <meta name="description" content="${escapeHtml(safeDescription)}">
    ${indexable ? '<meta name="robots" content="index,follow">' : '<meta name="robots" content="noindex">'}
    <meta property="og:type" content="website">
    <meta property="og:site_name" content="Promptbanken">
    <meta property="og:title" content="${escapeHtml(fullTitle)}">
    <meta property="og:description" content="${escapeHtml(safeDescription)}">
    <meta property="og:url" content="${escapeHtml(absoluteUrl(canonicalPath))}">
    <meta property="og:image" content="${escapeHtml(absoluteUrl('/brand-mark.png'))}">
    <meta name="twitter:card" content="summary">
    <link rel="canonical" href="${escapeHtml(absoluteUrl(canonicalPath))}">
    <link rel="stylesheet" href="/style.css">
</head>`;
}

function siteHeader() {
    return `<header class="landing-topbar">
        <a class="landing-brand" href="/index.html" aria-label="Promptbanken startsida">Promptbanken</a>
        <nav class="landing-nav" aria-label="Huvudlänkar">
            <a href="/paket/">Paket</a>
            <a href="/promptbanken.html">Katalog</a>
            <a href="/about.html">Om</a>
        </nav>
    </header>`;
}

function siteFooter() {
    return `<footer class="landing-footer">
        <p>Promptbanken — öppet bibliotek för arbete med AI.</p>
        <p><a href="/privacy.html">Integritet</a> · <a href="/terms.html">Villkor</a></p>
    </footer>`;
}

function breadcrumbs(trail) {
    const items = trail
        .map((item, index) => {
            const isLast = index === trail.length - 1;
            return isLast
                ? `<li aria-current="page">${escapeHtml(item.name)}</li>`
                : `<li><a href="${escapeHtml(item.path)}">${escapeHtml(item.name)}</a></li>`;
        })
        .join('\n            ');

    return `<nav class="breadcrumbs" aria-label="Brödsmulor">
        <ol>
            ${items}
        </ol>
    </nav>`;
}

// JSON.stringify produces valid JSON but does not escape characters that are
// unsafe inside an HTML <script> element (e.g. "<" can break out of the
// script context via "</script>" or be sniffed as markup by some parsers).
// Escape those characters after stringifying so any database-sourced text
// embedded in JSON-LD can never inject markup.
function jsonLdScript(data) {
    return JSON.stringify(data)
        .replace(/</g, '\\u003c')
        .replace(/>/g, '\\u003e')
        .replace(/&/g, '\\u0026');
}

function breadcrumbJsonLd(trail) {
    return jsonLdScript({
        '@context': 'https://schema.org',
        '@type': 'BreadcrumbList',
        itemListElement: trail.map((item, index) => ({
            '@type': 'ListItem',
            position: index + 1,
            name: item.name,
            item: absoluteUrl(item.path)
        }))
    });
}

function itemListJsonLd(prompts) {
    return jsonLdScript({
        '@context': 'https://schema.org',
        '@type': 'ItemList',
        itemListElement: prompts.map((prompt, index) => ({
            '@type': 'ListItem',
            position: index + 1,
            name: prompt.step_title || prompt.title || ''
        }))
    });
}

function section(heading, body) {
    if (!hasText(body)) return '';
    return `<section class="paket-section">
            <h2>${escapeHtml(heading)}</h2>
            <p>${escapeHtml(body)}</p>
        </section>`;
}

// Statiska paketsidor saknar appens JavaScript, så en besökare som kommer
// från sökmotor och läser sidan utan att klicka vidare syns annars inte alls
// i statistiken. Skickar en anonym package_page_view: ingen personuppgift,
// ingen cookie, ingen identifierare -- bara paketets slug. Anropet är
// medvetet tyst: statistik får aldrig påverka sidans funktion.
function usageBeacon(slug, supabase) {
    if (!supabase?.url || !supabase?.anonKey) return '';

    return `<script>
        (function () {
            try {
                fetch(${JSON.stringify(`${supabase.url}/rest/v1/rpc/track_library_usage_event`)}, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        apikey: ${JSON.stringify(supabase.anonKey)},
                        Authorization: 'Bearer ' + ${JSON.stringify(supabase.anonKey)}
                    },
                    body: JSON.stringify({
                        p_source: 'web',
                        p_event_type: 'package_page_view',
                        p_package_slug: ${JSON.stringify(slug)}
                    }),
                    keepalive: true
                }).catch(function () {});
            } catch (error) {}
        })();
    </script>`;
}

export function renderPackagePage({ pkg, prompts, related, indexable, supabase }) {
    const trail = [
        { name: 'Hem', path: '/' },
        { name: 'Paket', path: '/paket/' },
        { name: pkg.title, path: packageUrl(pkg.slug) }
    ];

    const editorialSections = [
        section('Vilket problem paketet löser', pkg.problem_text),
        section('Vem det är för', pkg.audience_label),
        section('När det passar', pkg.when_to_use),
        section('Vad du får ut', pkg.outcome_text)
    ].filter(Boolean).join('\n        ');

    const promptItems = prompts
        .map((prompt, index) => `<li class="paket-step">
                <h3>${escapeHtml(prompt.step_title || prompt.title || `Steg ${index + 1}`)}</h3>
                ${hasText(prompt.step_intro) ? `<p>${escapeHtml(prompt.step_intro)}</p>` : ''}
                ${hasText(prompt.summary) ? `<p class="paket-step-summary">${escapeHtml(prompt.summary)}</p>` : ''}
            </li>`)
        .join('\n            ');

    const relatedSection = related.length
        ? `<section class="paket-section paket-related">
            <h2>Relaterade paket</h2>
            <ul>
                ${related.map((item) => `<li><a href="${escapeHtml(packageUrl(item.slug))}">${escapeHtml(item.title)}</a>${hasText(item.summary) ? ` — ${escapeHtml(item.summary)}` : ''}</li>`).join('\n                ')}
            </ul>
        </section>`
        : '';

    const tagList = Array.isArray(pkg.tags) && pkg.tags.length
        ? `<p class="paket-tags">${pkg.tags.map((tag) => `<a href="/paket/#${escapeHtml(areaAnchor(pkg.area))}">${escapeHtml(tag)}</a>`).join(' · ')}</p>`
        : '';

    return `<!DOCTYPE html>
<html lang="sv">
${head({
        title: hasText(pkg.title) ? pkg.title : pkg.slug,
        description: pkg.summary || pkg.intro_text || '',
        canonicalPath: packageUrl(pkg.slug),
        indexable
    })}
<body class="paket-page">
    ${siteHeader()}
    <main>
        ${breadcrumbs(trail)}
        <article class="paket-article">
            <h1>${escapeHtml(pkg.title)}</h1>
            <p class="paket-lead">${escapeHtml(pkg.summary)}</p>
            <p class="paket-source">Av Promptbanken</p>
            ${hasText(pkg.intro_text) ? `<p class="paket-intro">${escapeHtml(pkg.intro_text)}</p>` : ''}
        ${editorialSections}
        <section class="paket-section paket-contents">
            <h2>Det här ingår</h2>
            <ol class="paket-steps">
            ${promptItems}
            </ol>
        </section>
        <p class="paket-cta">
            <a class="landing-primary" href="/promptbanken.html?package=${escapeHtml(pkg.slug)}">Öppna paketet i Promptbanken</a>
        </p>
        ${relatedSection}
        ${tagList}
        </article>
    </main>
    ${siteFooter()}
    <script type="application/ld+json">${breadcrumbJsonLd(trail)}</script>
    <script type="application/ld+json">${itemListJsonLd(prompts)}</script>
    ${usageBeacon(pkg.slug, supabase)}
</body>
</html>
`;
}

export function renderPackageIndexPage({ groups, indexable }) {
    const trail = [
        { name: 'Hem', path: '/' },
        { name: 'Paket', path: '/paket/' }
    ];

    const groupSections = groups
        .map((group) => `<section class="paket-group" id="${escapeHtml(areaAnchor(group.area))}">
            <h2>${escapeHtml(group.label)}</h2>
            <ul class="paket-group-list">
                ${group.packages.map((pkg) => `<li>
                    <a href="${escapeHtml(packageUrl(pkg.slug))}">${escapeHtml(pkg.title)}</a>
                    ${hasText(pkg.summary) ? `<p>${escapeHtml(pkg.summary)}</p>` : ''}
                </li>`).join('\n                ')}
            </ul>
        </section>`)
        .join('\n        ');

    return `<!DOCTYPE html>
<html lang="sv">
${head({
        title: 'Promptpaket och AI-arbetssätt',
        description: 'Färdiga promptpaket och AI-arbetssätt för riktiga arbetsuppgifter, sorterade efter område.',
        canonicalPath: '/paket/',
        indexable
    })}
<body class="paket-index-page">
    ${siteHeader()}
    <main>
        ${breadcrumbs(trail)}
        <h1>Promptpaket och AI-arbetssätt</h1>
        <p class="paket-lead">Färdiga paket för riktiga arbetsuppgifter — välj område nedan.</p>
        ${groupSections}
    </main>
    ${siteFooter()}
    <script type="application/ld+json">${breadcrumbJsonLd(trail)}</script>
</body>
</html>
`;
}
