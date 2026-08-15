// scripts/catalog-page-lib.mjs
// Rena hjälpfunktioner för generatorn av statiska katalogsidor.
// Se docs/superpowers/specs/2026-08-15-statiska-paketsidor-seo-design.md.

export const SITE_ORIGIN = 'https://app.promptbanken.se';

export const SAFE_SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export function isSafeSlug(value) {
    return typeof value === 'string' && SAFE_SLUG.test(value);
}

export function escapeHtml(value) {
    if (value === null || value === undefined) return '';
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

// Tröskeln finns för att undvika tunna landningssidor: ett paket måste ha
// redaktionell inledning och tillräckligt innehåll för att förtjäna
// indexering. is_indexable låter admin åsidosätta i båda riktningarna.
export function isIndexable(pkg, promptCount) {
    if (pkg?.is_indexable === true) return true;
    if (pkg?.is_indexable === false) return false;
    const hasIntro = typeof pkg?.intro_text === 'string' && pkg.intro_text.trim() !== '';
    return hasIntro && promptCount >= 3;
}

export function packageUrl(slug) {
    return `/paket/${slug}/`;
}

export function absoluteUrl(path) {
    return `${SITE_ORIGIN}${path}`;
}

export function buildSitemap(urls) {
    const unique = [...new Set(urls)];
    const entries = unique.map((url) => `  <url><loc>${escapeHtml(url)}</loc></url>`).join('\n');
    return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${entries}
</urlset>
`;
}

// Samma å/ä/ö-normalisering som SkillRouter i mcp-server/server/skill_router.py
// använder för svensk textmatchning.
export function areaAnchor(area) {
    if (!area) return 'omrade-ovriga';
    const slug = String(area)
        .toLowerCase()
        .replace(/å/g, 'a')
        .replace(/ä/g, 'a')
        .replace(/ö/g, 'o')
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '');
    return slug ? `omrade-${slug}` : 'omrade-ovriga';
}

export function groupPackagesByArea(packages) {
    const byArea = new Map();
    const withoutArea = [];

    for (const pkg of packages) {
        const area = pkg?.area || null;
        if (!area) {
            withoutArea.push(pkg);
            continue;
        }
        if (!byArea.has(area)) byArea.set(area, []);
        byArea.get(area).push(pkg);
    }

    const groups = [...byArea.entries()]
        .sort(([a], [b]) => a.localeCompare(b, 'sv'))
        .map(([area, items]) => ({ area, label: area, packages: items }));

    if (withoutArea.length) {
        groups.push({ area: null, label: 'Övriga paket', packages: withoutArea });
    }

    return groups;
}
