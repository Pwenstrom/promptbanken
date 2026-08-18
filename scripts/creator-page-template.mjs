// scripts/creator-page-template.mjs
// HTML-mallar för statiska creator-profilsidor. Följer samma head()/
// siteHeader()/siteFooter()/breadcrumbs()-mönster som catalog-page-template.mjs
// så sidorna ärver designsystemet och SEO-strukturen.

import { escapeHtml, absoluteUrl } from './catalog-page-lib.mjs';
import { creatorUrl, initialsFrom, safeExternalUrl } from './creator-page-lib.mjs';

function hasText(value) {
    return typeof value === 'string' && value.trim() !== '';
}

// Kopierad från catalog-page-template.mjs (inte exporterad därifrån) för att
// hålla referensfilen orörd.
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
    <meta property="og:type" content="profile">
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
            <a href="/creator/">Creators</a>
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

// Samma JSON-LD-escaping som catalog-page-template.mjs: JSON.stringify
// escapar inte "<" som kan bryta ut ur <script>-elementet.
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

function personJsonLd(profile) {
    return jsonLdScript({
        '@context': 'https://schema.org',
        '@type': 'Person',
        name: profile.display_name,
        url: absoluteUrl(creatorUrl(profile.slug))
    });
}

// Renderar en extern länk bara om safeExternalUrl släpper igenom den.
// rel="nofollow noopener" + target="_blank" på alla externa länkar: nofollow
// eftersom vi inte redaktionellt granskar creator-innehåll, noopener för att
// skydda mot reverse tabnabbing.
function externalLink(label, url) {
    const safe = safeExternalUrl(url);
    if (!safe) return '';
    return `<a href="${escapeHtml(safe)}" rel="nofollow noopener" target="_blank">${escapeHtml(label)}</a>`;
}

function emptyStateSection(heading) {
    return `<section class="creator-section">
            <h2>${escapeHtml(heading)}</h2>
            <p>Inget publicerat ännu.</p>
        </section>`;
}

export function renderCreatorPage({ profile, indexable }) {
    const trail = [
        { name: 'Hem', path: '/' },
        { name: 'Creators', path: '/creator/' },
        { name: profile.display_name, path: creatorUrl(profile.slug) }
    ];

    const initials = initialsFrom(profile.display_name);

    const competenceAreas = Array.isArray(profile.competence_areas) ? profile.competence_areas : [];

    const linkItems = [
        externalLink('Webbplats', profile.website_url),
        externalLink('LinkedIn', profile.linkedin_url)
    ].filter(Boolean);
    const links = linkItems.length
        ? `<div class="creator-links">\n            ${linkItems.join('\n            ')}\n        </div>`
        : '';

    return `<!DOCTYPE html>
<html lang="sv">
${head({
        title: profile.display_name,
        description: profile.bio_short || '',
        canonicalPath: creatorUrl(profile.slug),
        indexable
    })}
<body class="creator-page">
    ${siteHeader()}
    <main>
        ${breadcrumbs(trail)}
        <article class="creator-article">
            <div class="creator-identity">
                <span class="creator-initials" aria-hidden="true">${escapeHtml(initials)}</span>
                <div>
                    <h1>${escapeHtml(profile.display_name)}</h1>
                    <p class="creator-badge">Creator på Promptbanken</p>
                </div>
            </div>
            ${hasText(profile.bio_short) ? `<p class="creator-lead">${escapeHtml(profile.bio_short)}</p>` : ''}
            ${hasText(profile.bio_long) ? `<p class="creator-bio">${escapeHtml(profile.bio_long)}</p>` : ''}
            ${hasText(profile.organisation) ? `<p class="creator-organisation"><strong>Organisation:</strong> ${escapeHtml(profile.organisation)}</p>` : ''}
            ${competenceAreas.length ? `<p class="creator-competence"><strong>Kompetensområden:</strong> ${competenceAreas.map((area) => escapeHtml(area)).join(', ')}</p>` : ''}
            ${links}
            ${emptyStateSection('Publicerade paket')}
            ${emptyStateSection('Publicerade prompts')}
            ${emptyStateSection('Workshopkrediter')}
        </article>
    </main>
    ${siteFooter()}
    <script type="application/ld+json">${breadcrumbJsonLd(trail)}</script>
    <script type="application/ld+json">${personJsonLd(profile)}</script>
</body>
</html>
`;
}

export function renderCreatorIndexPage({ profiles, indexable }) {
    const trail = [
        { name: 'Hem', path: '/' },
        { name: 'Creators', path: '/creator/' }
    ];

    const list = profiles.length
        ? `<ul class="creator-index-list">
            ${profiles.map((profile) => `<li>
                <a href="${escapeHtml(creatorUrl(profile.slug))}">${escapeHtml(profile.display_name)}</a>
                ${hasText(profile.bio_short) ? `<p>${escapeHtml(profile.bio_short)}</p>` : ''}
            </li>`).join('\n            ')}
        </ul>`
        : '<p>Inget publicerat ännu.</p>';

    return `<!DOCTYPE html>
<html lang="sv">
${head({
        title: 'Creators',
        description: 'Creators som delar paket och prompts på Promptbanken.',
        canonicalPath: '/creator/',
        indexable
    })}
<body class="creator-index-page">
    ${siteHeader()}
    <main>
        ${breadcrumbs(trail)}
        <h1>Creators</h1>
        <p class="creator-lead">Creators på Promptbanken.</p>
        ${list}
    </main>
    ${siteFooter()}
    <script type="application/ld+json">${breadcrumbJsonLd(trail)}</script>
</body>
</html>
`;
}
