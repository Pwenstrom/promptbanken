import { createClient } from '@supabase/supabase-js';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function loadLocalEnvFile() {
  const envPath = resolve(process.cwd(), '.env.seed.local');
  if (!existsSync(envPath)) {
    return;
  }

  const lines = readFileSync(envPath, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }

    const separatorIndex = trimmed.indexOf('=');
    if (separatorIndex === -1) {
      continue;
    }

    const key = trimmed.slice(0, separatorIndex).trim();
    const value = trimmed.slice(separatorIndex + 1).trim().replace(/^["']|["']$/g, '');
    if (key && !process.env[key]) {
      process.env[key] = value;
    }
  }
}

loadLocalEnvFile();

const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const defaultPassword = process.env.TEST_USER_PASSWORD || 'Promptbanken-Test-2026!';

function describeKey(value) {
  if (!value) {
    return 'saknas';
  }

  if (value.includes('din-service-role-key') || value.includes('KListra-in')) {
    return 'placeholder';
  }

  if (value.startsWith('sb_publishable_')) {
    return 'publishable key';
  }

  if (value.startsWith('sb_secret_')) {
    return `secret key (${value.slice(0, 12)}...)`;
  }

  const jwtParts = value.split('.');
  if (jwtParts.length === 3) {
    return `JWT/service_role-liknande (${value.slice(0, 8)}...)`;
  }

  return `okänd typ (${value.slice(0, 8)}...)`;
}

if (!supabaseUrl || !serviceRoleKey) {
  console.error('Saknar SUPABASE_URL/VITE_SUPABASE_URL eller SUPABASE_SERVICE_ROLE_KEY.');
  console.error('Skapa gärna .env.seed.local med SUPABASE_URL och SUPABASE_SERVICE_ROLE_KEY.');
  console.error('Exempel: $env:SUPABASE_SERVICE_ROLE_KEY="..."; npm run seed:test-users');
  process.exit(1);
}

if (serviceRoleKey.includes('din-service-role-key') || serviceRoleKey.includes('KListra-in')) {
  console.error('SUPABASE_SERVICE_ROLE_KEY är fortfarande en platshållare.');
  process.exit(1);
}

if (serviceRoleKey.startsWith('sb_publishable_')) {
  console.error('SUPABASE_SERVICE_ROLE_KEY är en publishable key. Auth-admin kräver service role/secret key.');
  process.exit(1);
}

console.log(`Supabase URL: ${supabaseUrl}`);
console.log(`Nyckeltyp: ${describeKey(serviceRoleKey)}`);

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

const users = [
  {
    email: 'free.user@test.se',
    role: 'editor',
    workspaceSlug: 'test-free-user',
    workspaceName: 'Test Free User',
    workspaceType: 'personal',
    plan: 'free'
  },
  {
    email: 'org.editor@test.se',
    role: 'editor',
    workspaceSlug: 'test-savsjo-kommun',
    workspaceName: 'Test Sävsjö kommun',
    workspaceType: 'organization',
    plan: 'start'
  },
  {
    email: 'org.admin@test.se',
    role: 'workspace_admin',
    workspaceSlug: 'test-savsjo-kommun',
    workspaceName: 'Test Sävsjö kommun',
    workspaceType: 'organization',
    plan: 'start'
  },
  {
    email: 'org.owner@test.se',
    role: 'workspace_owner',
    workspaceSlug: 'test-savsjo-kommun',
    workspaceName: 'Test Sävsjö kommun',
    workspaceType: 'organization',
    plan: 'start'
  },
  {
    email: 'org.viewer@test.se',
    role: 'viewer',
    workspaceSlug: 'test-savsjo-kommun',
    workspaceName: 'Test Sävsjö kommun',
    workspaceType: 'organization',
    plan: 'start'
  },
  {
    email: 'org-b.admin@test.se',
    role: 'workspace_admin',
    workspaceSlug: 'testkommun-b',
    workspaceName: 'Testkommun B',
    workspaceType: 'organization',
    plan: 'start'
  },
  {
    email: 'platform.admin@test.se',
    role: 'platform_owner',
    workspaceSlug: 'test-platform',
    workspaceName: 'Test Platform',
    workspaceType: 'organization',
    plan: 'enterprise'
  }
];

async function findUserByEmail(email) {
  let page = 1;
  const perPage = 1000;

  while (true) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage });
    if (error) {
      throw error;
    }

    const user = data.users.find((item) => item.email?.toLowerCase() === email.toLowerCase());
    if (user) {
      return user;
    }

    if (data.users.length < perPage) {
      return null;
    }

    page += 1;
  }
}

async function upsertAuthUser(email) {
  const existing = await findUserByEmail(email);
  if (existing) {
    const { data, error } = await supabase.auth.admin.updateUserById(existing.id, {
      password: defaultPassword,
      email_confirm: true
    });
    if (error) {
      throw error;
    }
    return data.user;
  }

  const { data, error } = await supabase.auth.admin.createUser({
    email,
    password: defaultPassword,
    email_confirm: true
  });
  if (error) {
    throw error;
  }
  return data.user;
}

async function ensureWorkspace(config, ownerUserId) {
  const { data: existing, error: findError } = await supabase
    .from('workspaces')
    .select('id')
    .eq('slug', config.workspaceSlug)
    .maybeSingle();

  if (findError) {
    throw findError;
  }

  if (existing) {
    const { error } = await supabase
      .from('workspaces')
      .update({
        name: config.workspaceName,
        type: config.workspaceType,
        plan: config.plan,
        owner_user_id: ownerUserId,
        max_public_items: config.workspaceType === 'personal' ? 3 : 25,
        max_documents: config.workspaceType === 'personal' ? 3 : 25
      })
      .eq('id', existing.id);
    if (error) {
      throw error;
    }
    return existing.id;
  }

  const { data, error } = await supabase
    .from('workspaces')
    .insert({
      name: config.workspaceName,
      slug: config.workspaceSlug,
      type: config.workspaceType,
      plan: config.plan,
      owner_user_id: ownerUserId,
      max_public_items: config.workspaceType === 'personal' ? 3 : 25,
      max_documents: config.workspaceType === 'personal' ? 3 : 25
    })
    .select('id')
    .single();

  if (error) {
    throw error;
  }

  return data.id;
}

async function upsertProfile(userId, workspaceId, role) {
  const { data: existing, error: findError } = await supabase
    .from('profiles')
    .select('id')
    .eq('user_id', userId)
    .eq('workspace_id', workspaceId)
    .maybeSingle();

  if (findError) {
    throw findError;
  }

  if (existing) {
    const { error } = await supabase
      .from('profiles')
      .update({ role })
      .eq('id', existing.id);
    if (error) {
      throw error;
    }
    return;
  }

  const { error } = await supabase
    .from('profiles')
    .insert({ user_id: userId, workspace_id: workspaceId, role });

  if (error) {
    throw error;
  }
}

const authUsers = new Map();

for (const config of users) {
  try {
    const user = await upsertAuthUser(config.email);
    authUsers.set(config.email, user);
  } catch (error) {
    if (error?.status === 401) {
      console.error('');
      console.error('Supabase nekade nyckeln med 401 Invalid API key.');
      console.error('Kontrollera att .env.seed.local innehåller en giltig, inte roterad, service role/secret key för exakt projektet ovan.');
      console.error('Kopiera inte VITE_SUPABASE_PUBLISHABLE_KEY hit.');
    }
    throw error;
  }
}

for (const config of users) {
  const user = authUsers.get(config.email);
  const owner = users.find((item) => item.workspaceSlug === config.workspaceSlug && (
    item.role === 'workspace_owner' || item.role === 'platform_owner' || item.workspaceType === 'personal'
  ));
  const ownerUser = authUsers.get(owner?.email || config.email);
  const workspaceId = await ensureWorkspace(config, ownerUser.id);
  await upsertProfile(user.id, workspaceId, config.role);
  console.log(`${config.email} -> ${config.workspaceSlug} (${config.role})`);
}

console.log('');
console.log(`Klart. Lösenord för alla testanvändare: ${defaultPassword}`);
