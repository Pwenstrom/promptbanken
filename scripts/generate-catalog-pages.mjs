// scripts/generate-catalog-pages.mjs
// Genererar statiska paketsidor efter `vite build`.
// I CI (env satt) failar scriptet bygget vid fel — hellre stoppat bygge än
// en deployad sajt utan paketsidor och med amputerad sitemap.
// Lokalt utan env hoppar det över med varning.

import { mkdir, readFile, writeFile } from 'node:fs/promises';
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
import { creatorUrl, isProfileIndexable } from './creator-page-lib.mjs';
import { renderCreatorPage, renderCreatorIndexPage } from './creator-page-template.mjs';

const DIST = 'dist';

// sitemap.xml i repo-roten är den enda mänskligt redigerbara källan för de
// statiska URL:erna. Vi läser <loc>-värdena därifrån istället för att
// duplicera dem här, så att en URL som läggs till i sitemap.xml faktiskt
// hamnar i produktion (se whole-branch review-anmärkning 3).
async function readStaticUrlsFromSitemap() {
    let xml;
    try {
        xml = await readFile('sitemap.xml', 'utf8');
    } catch (error) {
        throw new Error(`kunde inte läsa sitemap.xml: ${error.message}`);
    }
    const urls = [...xml.matchAll(/<loc>(.*?)<\/loc>/g)].map((match) => match[1].trim());
    if (urls.length === 0) {
        throw new Error('sitemap.xml innehåller inga <loc>-poster.');
    }
    return urls;
}

const supabaseUrl = process.env.VITE_SUPABASE_URL;
const supabaseKey = process.env.VITE_SUPABASE_PUBLISHABLE_KEY;

if (!supabaseUrl || !supabaseKey) {
    if (process.env.CI) {
        console.error(
            '[generate-catalog-pages] VITE_SUPABASE_URL/VITE_SUPABASE_PUBLISHABLE_KEY saknas i CI — avbryter bygget istället för att deploya utan paketsidor.'
        );
        process.exit(1);
    }
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
    const staticUrls = await readStaticUrlsFromSitemap();

    const packages = await rpc('list_published_packages', {
        p_context_keys: ['generell'],
        p_package_type: null
    });

    const usable = packages.filter((pkg) => {
        if (isSafeSlug(pkg.slug)) return true;
        console.warn(`[generate-catalog-pages] hoppar över paket med osäker slug: ${JSON.stringify(pkg.slug)}`);
        return false;
    });

    // Indexability måste vara känd för ALLA paket innan vi renderar någon
    // sida, annars kan en "related"-länk på en tidigt renderad sida peka på
    // ett senare paket som visar sig vara noindex (review-anmärkning 5).
    const usableWithPrompts = [];
    for (const pkg of usable) {
        const prompts = await rpc('list_published_package_prompts', {
            p_package_slug: pkg.slug,
            p_context_keys: ['generell']
        });
        usableWithPrompts.push({ pkg, prompts, indexable: isIndexable(pkg, prompts.length) });
    }

    const indexableSet = usableWithPrompts.filter((entry) => entry.indexable);
    const indexableUrls = indexableSet.map((entry) => absoluteUrl(packageUrl(entry.pkg.slug)));
    const indexablePackages = indexableSet.map((entry) => entry.pkg);

    for (const { pkg, prompts, indexable } of usableWithPrompts) {
        const related = indexableSet
            .filter((entry) => entry.pkg.slug !== pkg.slug && entry.pkg.area && entry.pkg.area === pkg.area)
            .slice(0, 4)
            .map(({ pkg: { slug, title, summary } }) => ({ slug, title, summary }));

        await writePage(
            `paket/${pkg.slug}`,
            renderPackagePage({
                pkg,
                prompts,
                related,
                indexable,
                supabase: { url: supabaseUrl, anonKey: supabaseKey }
            })
        );
    }

    // /paket/ har inget att erbjuda utan minst ett indexerbart paket -- då
    // ska översiktssidan varken indexeras eller listas i sitemapen
    // (review-anmärkning 6).
    const indexOverviewIsIndexable = indexablePackages.length > 0;

    await writePage(
        'paket',
        renderPackageIndexPage({ groups: groupPackagesByArea(indexablePackages), indexable: indexOverviewIsIndexable })
    );

    const profiles = await rpc('list_published_creator_profiles', {});

    const usableProfiles = profiles.filter((profile) => {
        if (isSafeSlug(profile.slug)) return true;
        console.warn(`[generate-catalog-pages] hoppar över profil med osäker slug: ${JSON.stringify(profile.slug)}`);
        return false;
    });

    const indexableProfiles = usableProfiles.filter(isProfileIndexable);
    const creatorUrls = indexableProfiles.map((profile) => absoluteUrl(creatorUrl(profile.slug)));

    for (const profile of usableProfiles) {
        await writePage(
            `creator/${profile.slug}`,
            renderCreatorPage({ profile, indexable: isProfileIndexable(profile) })
        );
    }

    // Utan minst en kvalificerad profil är översikten en tom sida -- den ska
    // varken indexeras eller ligga i sitemap.
    const creatorIndexIsIndexable = indexableProfiles.length > 0;
    await writePage(
        'creator',
        renderCreatorIndexPage({ profiles: indexableProfiles, indexable: creatorIndexIsIndexable })
    );

    const sitemap = buildSitemap([
        ...staticUrls,
        ...(indexOverviewIsIndexable ? [absoluteUrl('/paket/')] : []),
        ...indexableUrls,
        ...(creatorIndexIsIndexable ? [absoluteUrl('/creator/')] : []),
        ...creatorUrls
    ]);
    await writeFile(join(DIST, 'sitemap.xml'), sitemap, 'utf8');

    console.log(
        `[generate-catalog-pages] ${usable.length} paketsidor skrivna, varav ${indexableUrls.length} indexerbara. ${usableProfiles.length} creatorprofiler skrivna, varav ${creatorUrls.length} indexerbara.`
    );
}

main().catch((error) => {
    console.error(`[generate-catalog-pages] ${error.message}`);
    process.exit(1);
});
