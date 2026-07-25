import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PROMPT_PACKAGE_MAPPING = {
  klarsprak: 'kommunikation',
  mejl: 'kommunikation',
  faq: 'kommunikation',
  kallelse: 'kommunikation',
  beslutsunderlag: 'beslutsberedning',
  rutin: 'processer',
  tvaversioner: 'kommunikation',
  informationsutskick: 'kommunikation',
  enkel_infografik: 'visuellt',
  illustration_informationsutskick: 'visuellt',
};

const PACKAGE_PRESENTATION = {
  kommunikation: { iconKey: 'message', colorTheme: 'blue' },
  processer: { iconKey: 'list', colorTheme: 'teal' },
  beslutsberedning: { iconKey: 'clipboard', colorTheme: 'slate' },
  visuellt: { iconKey: 'image', colorTheme: 'orange' },
};

function sqlString(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

export function sqlDollarQuote(value, preferredTag = 'text') {
  const sanitizedTag = String(preferredTag).replaceAll(/[^a-zA-Z0-9_]/g, '_') || 'text';
  const baseTag = /^[a-zA-Z_]/.test(sanitizedTag) ? sanitizedTag : `text_${sanitizedTag}`;
  let tag = baseTag;
  let suffix = 0;

  while (String(value).includes(`$${tag}$`)) {
    suffix += 1;
    tag = `${baseTag}_${suffix}`;
  }

  return `$${tag}$${value}$${tag}$`;
}

export async function loadParameterizedPromptSeeds(repoRoot) {
  const configPath = path.join(repoRoot, 'prompts.json');
  const config = JSON.parse(await readFile(configPath, 'utf8'));
  const promptsById = new Map(config.prompts.map((prompt) => [prompt.id, prompt]));

  return Promise.all(Object.entries(PROMPT_PACKAGE_MAPPING).map(async ([slug, packageSlug], index) => {
    const prompt = promptsById.get(slug);
    if (!prompt?.parameter_schema) {
      throw new Error(`Prompten ${slug} saknar parameter_schema i prompts.json`);
    }

    const presentation = PACKAGE_PRESENTATION[packageSlug];
    const promptText = (await readFile(path.join(repoRoot, prompt.file), 'utf8')).trim();

    return {
      slug,
      packageSlug,
      sortOrder: 100 + index,
      iconKey: presentation.iconKey,
      colorTheme: presentation.colorTheme,
      title: prompt.title,
      summary: prompt.description,
      promptText,
      parameterSchema: prompt.parameter_schema,
      defaultBindings: prompt.default_bindings || {},
      bindingOverrides: prompt.binding_overrides || [],
    };
  }));
}

function buildSeedRow(seed) {
  const tag = seed.slug.replaceAll(/[^a-zA-Z0-9_]/g, '_');
  return [
    sqlString(seed.slug),
    sqlString(seed.packageSlug),
    seed.sortOrder,
    sqlString(seed.iconKey),
    sqlString(seed.colorTheme),
    sqlDollarQuote(seed.title, `title_${tag}`),
    sqlDollarQuote(seed.summary, `summary_${tag}`),
    sqlDollarQuote(seed.promptText, `prompt_${tag}`),
    `${sqlDollarQuote(JSON.stringify(seed.parameterSchema), `schema_${tag}`)}::jsonb`,
    `${sqlDollarQuote(JSON.stringify(seed.defaultBindings), `defaults_${tag}`)}::jsonb`,
    `${sqlDollarQuote(JSON.stringify(seed.bindingOverrides), `overrides_${tag}`)}::jsonb`,
  ].join(', ');
}

export function buildParameterizedCatalogMigration(seeds) {
  if (seeds.length !== 10) {
    throw new Error(`Förväntade 10 parametriserade prompter, fick ${seeds.length}`);
  }

  const seedRows = seeds.map((seed) => `    (${buildSeedRow(seed)})`).join(',\n');

  return `-- Genererad av scripts/generate-catalog-parameterized-prompts.mjs.
-- Synkar de tio filbaserade parametriserade prompterna till Öppen katalog.
-- Kör efter 20260725133000_catalog_parameter_schemas.sql.

create temporary table parameterized_catalog_prompt_seed (
    slug text primary key,
    package_slug text not null,
    sort_order integer not null,
    icon_key text not null,
    color_theme text not null,
    title text not null,
    summary text not null,
    prompt_text text not null,
    parameter_schema jsonb not null,
    default_bindings jsonb not null,
    binding_overrides jsonb not null
);

insert into parameterized_catalog_prompt_seed (
    slug,
    package_slug,
    sort_order,
    icon_key,
    color_theme,
    title,
    summary,
    prompt_text,
    parameter_schema,
    default_bindings,
    binding_overrides
) values
${seedRows};

do $$
declare
    missing_packages text;
begin
    select string_agg(missing.package_slug, ', ' order by missing.package_slug)
    into missing_packages
    from (
        select distinct seed.package_slug
        from parameterized_catalog_prompt_seed seed
        left join public.catalog_packages package on package.slug = seed.package_slug
        where package.id is null
    ) missing;

    if missing_packages is not null then
        raise exception 'Katalogpaket saknas: %', missing_packages;
    end if;
end
$$;

insert into public.catalog_prompts (
    slug,
    status,
    prompt_kind,
    icon_key,
    color_theme
)
select
    slug,
    'published',
    'prompt',
    icon_key,
    color_theme
from parameterized_catalog_prompt_seed
on conflict (slug) do update set
    status = excluded.status,
    prompt_kind = excluded.prompt_kind,
    icon_key = excluded.icon_key,
    color_theme = excluded.color_theme;

insert into public.catalog_prompt_variants (
    prompt_id,
    context_key,
    title,
    summary,
    prompt_text,
    audience_label,
    tone_hint,
    parameter_schema,
    default_bindings,
    binding_overrides
)
select
    prompt.id,
    'generell',
    seed.title,
    seed.summary,
    seed.prompt_text,
    seed.default_bindings ->> 'malgrupp',
    seed.default_bindings ->> 'ton',
    seed.parameter_schema,
    seed.default_bindings,
    seed.binding_overrides
from parameterized_catalog_prompt_seed seed
join public.catalog_prompts prompt on prompt.slug = seed.slug
on conflict (prompt_id, context_key) do update set
    prompt_text = excluded.prompt_text,
    title = excluded.title,
    summary = excluded.summary,
    audience_label = excluded.audience_label,
    tone_hint = excluded.tone_hint,
    parameter_schema = excluded.parameter_schema,
    default_bindings = excluded.default_bindings,
    binding_overrides = excluded.binding_overrides;

insert into public.catalog_package_items (
    package_id,
    prompt_id,
    sort_order,
    step_title,
    step_intro,
    is_required
)
select
    package.id,
    prompt.id,
    seed.sort_order,
    seed.title,
    seed.summary,
    true
from parameterized_catalog_prompt_seed seed
join public.catalog_packages package on package.slug = seed.package_slug
join public.catalog_prompts prompt on prompt.slug = seed.slug
on conflict (package_id, prompt_id) do update set
    sort_order = excluded.sort_order,
    step_title = excluded.step_title,
    step_intro = excluded.step_intro,
    is_required = excluded.is_required;

drop table parameterized_catalog_prompt_seed;
`;
}

async function main() {
  const scriptPath = fileURLToPath(import.meta.url);
  const repoRoot = path.resolve(path.dirname(scriptPath), '..');
  const outputPath = process.argv[2];

  if (!outputPath) {
    throw new Error('Ange sökvägen till migrationsfilen som första argument.');
  }

  const seeds = await loadParameterizedPromptSeeds(repoRoot);
  const sql = buildParameterizedCatalogMigration(seeds);
  await writeFile(path.resolve(repoRoot, outputPath), sql, 'utf8');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
