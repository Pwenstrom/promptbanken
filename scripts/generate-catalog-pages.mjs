// scripts/generate-catalog-pages.mjs
// Genererar statiska paketsidor efter `vite build`.
// I CI (env satt) failar scriptet bygget vid fel — hellre stoppat bygge än
// en deployad sajt utan paketsidor och med amputerad sitemap.
// Lokalt utan env hoppar det över med varning.

import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import {
    isSafeSlug,
    isIndexable,
    buildSitemap,
    packageUrl,
    absoluteUrl,
    groupPackagesByArea
} from './catalog-page-lib.mjs';
import { renderPackagePage, renderPackageIndexPage } from './catalog-page-template.mjs';

const DIST = 'dist';

// Behålls oförändrad från den tidigare handskrivna sitemap.xml.
const STATIC_URLS = [
    '/',
    '/index.html',
    '/promptbanken.html',
    '/about.html',
    '/help.html',
    '/mcp.html',
    '/privacy.html',
    '/terms.html',
    '/prompts.html',
    '/prompts.json',
    '/llms.txt',
    '/prompts/tydlighetskoll.txt',
    '/prompts/klarsprak.txt',
    '/prompts/mejl.txt',
    '/prompts/faq.txt',
    '/prompts/checklista.txt',
    '/prompts/kallelse.txt',
    '/prompts/beslutsunderlag.txt',
    '/prompts/rutin.txt',
    '/prompts/tvaversioner.txt',
    '/prompts/reflektion.txt',
    '/prompts/samtalskompas.txt',
    '/prompts/sammanfattning.txt',
    '/prompts/anteckningar.txt',
    '/prompts/diskussionsfragor.txt',
    '/prompts/nyckelord.txt',
    '/prompts/informationsutskick.txt'
];

const supabaseUrl = process.env.VITE_SUPABASE_URL;
const supabaseKey = process.env.VITE_SUPABASE_PUBLISHABLE_KEY;

if (!supabaseUrl || !supabaseKey) {
    console.warn(
        '[generate-catalog-pages] VITE_SUPABASE_URL/VITE_SUPABASE_PUBLISHABLE_KEY saknas — hoppar över generering av paketsidor.'
    );
    process.exit(0);
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function rpc(name, args) {
    const { data, error } = await supabase.rpc(name, args);
    if (error) {
        throw new Error(`RPC ${name} misslyckades: ${error.message}`);
    }
    return data || [];
}

async function writePage(path, html) {
    await mkdir(join(DIST, path), { recursive: true });
    await writeFile(join(DIST, path, 'index.html'), html, 'utf8');
}

async function main() {
    const packages = await rpc('list_published_packages', {
        p_context_keys: ['generell'],
        p_package_type: null
    });

    const usable = packages.filter((pkg) => {
        if (isSafeSlug(pkg.slug)) return true;
        console.warn(`[generate-catalog-pages] hoppar över paket med osäker slug: ${JSON.stringify(pkg.slug)}`);
        return false;
    });

    const indexableUrls = [];
    const indexablePackages = [];

    for (const pkg of usable) {
        const prompts = await rpc('list_published_package_prompts', {
            p_package_slug: pkg.slug,
            p_context_keys: ['generell']
        });

        const indexable = isIndexable(pkg, prompts.length);

        const related = usable
            .filter((other) => other.slug !== pkg.slug && other.area && other.area === pkg.area)
            .slice(0, 4)
            .map(({ slug, title, summary }) => ({ slug, title, summary }));

        await writePage(
            `paket/${pkg.slug}`,
            renderPackagePage({ pkg, prompts, related, indexable })
        );

        if (indexable) {
            indexableUrls.push(absoluteUrl(packageUrl(pkg.slug)));
            indexablePackages.push(pkg);
        }
    }

    await writePage(
        'paket',
        renderPackageIndexPage({ groups: groupPackagesByArea(indexablePackages) })
    );

    const sitemap = buildSitemap([
        ...STATIC_URLS.map((path) => absoluteUrl(path)),
        absoluteUrl('/paket/'),
        ...indexableUrls
    ]);
    await writeFile(join(DIST, 'sitemap.xml'), sitemap, 'utf8');

    console.log(
        `[generate-catalog-pages] ${usable.length} paketsidor skrivna, varav ${indexableUrls.length} indexerbara.`
    );
}

main().catch((error) => {
    console.error(`[generate-catalog-pages] ${error.message}`);
    process.exit(1);
});
