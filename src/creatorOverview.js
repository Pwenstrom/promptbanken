// Creator-översikten.
//
// Svarar på tre frågor inom en skärmhöjd: vad väntar på mig, vad höll jag
// på med, vad kan jag börja på. All data kommer från ett enda anrop —
// fyra anrop för fyra sektioner ger en sida som byggs i ryck.
//
// Se docs/superpowers/specs/2026-08-24-creator-ux-structure.md.

import { requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const STATUS_LABELS = {
    draft: 'Privat',
    review: 'Under granskning',
    published: 'Publicerad',
    archived: 'Arkiverad',
    changes_requested: 'Ändringar begärda i Open',
    rejected: 'Avslagen i Open'
};

const KIND_LABELS = { prompt: 'Prompt', package: 'Paket' };
const KIND_PAGES = { prompt: 'creator-content.html', package: 'creator-packages.html' };

function el(selector, root = document) {
    return root.querySelector(selector);
}

// Relativ tid utan bibliotek. Intl.RelativeTimeFormat finns i alla
// webbläsare vi bryr oss om och ger svensk formulering gratis.
function relativeTime(value) {
    if (!value) return '';
    const formatter = new Intl.RelativeTimeFormat('sv', { numeric: 'auto' });
    const diffMs = new Date(value).getTime() - Date.now();
    const units = [
        ['day', 86400000],
        ['hour', 3600000],
        ['minute', 60000]
    ];
    for (const [unit, ms] of units) {
        if (Math.abs(diffMs) >= ms) {
            return formatter.format(Math.round(diffMs / ms), unit);
        }
    }
    return 'nyss';
}

// Samma mönster som renderOnboardingChecklist i admin.js: växla .is-done
// och ✓/○ per steg. Klar checklista döljs helt -- den har gjort sitt.
function renderChecklist(checklist) {
    const section = el('[data-overview-onboarding-section]');
    if (!checklist) {
        section.hidden = true;
        return;
    }

    const steps = {
        profile: Boolean(checklist.has_profile),
        prompt: Boolean(checklist.has_prompt),
        package: Boolean(checklist.has_package),
        share: Boolean(checklist.has_share)
    };

    Object.entries(steps).forEach(([step, done]) => {
        const item = section.querySelector(`[data-onboarding-step="${step}"]`);
        if (!item) return;
        item.classList.toggle('is-done', done);
        const check = item.querySelector('.onboarding-check');
        if (check) check.textContent = done ? '✓' : '○';
    });

    section.hidden = Object.values(steps).every(Boolean);
}

function renderNeedsAction(items) {
    const section = el('[data-overview-needs-action-section]');
    const list = el('[data-overview-needs-action]');
    const template = el('[data-overview-action-template]');

    if (!items.length) {
        section.hidden = true;
        return;
    }

    list.innerHTML = '';
    items.forEach((item) => {
        const node = template.content.firstElementChild.cloneNode(true);
        el('[data-action-title]', node).textContent = item.title;
        el('[data-action-kind]', node).textContent =
            `${KIND_LABELS[item.kind]} · ${STATUS_LABELS[item.status] || item.status}`;
        el('[data-action-note]', node).textContent =
            ['archived', 'rejected'].includes(item.status)
                ? `Avslogs: ${item.review_note}`
                : `Skickades tillbaka: ${item.review_note}`;
        el('[data-action-link]', node).href = KIND_PAGES[item.kind];
        list.appendChild(node);
    });
    section.hidden = false;
}

function renderRecent(items) {
    const list = el('[data-overview-recent]');
    const empty = el('[data-overview-recent-empty]');

    list.innerHTML = '';
    if (!items.length) {
        list.hidden = true;
        empty.hidden = false;
        return;
    }

    items.forEach((item) => {
        const li = document.createElement('li');
        const link = document.createElement('a');
        link.href = KIND_PAGES[item.kind];
        link.textContent = item.title;

        const meta = document.createElement('span');
        meta.className = 'overview-recent-meta';
        meta.textContent =
            `${KIND_LABELS[item.kind]} · ${STATUS_LABELS[item.status] || item.status} · ${relativeTime(item.updated_at)}`;

        li.append(link, meta);
        list.appendChild(li);
    });
    list.hidden = false;
    empty.hidden = true;
}

// Siffrorna visas först när något är publicerat. Innan dess är de bara
// nollor som ser ut som ett misslyckande.
function renderStats(stats) {
    const section = el('[data-overview-stats-section]');
    const container = el('[data-overview-stats]');

    const published = (stats.published_prompts || 0) + (stats.published_packages || 0);
    if (published === 0) {
        section.hidden = true;
        return;
    }

    const cells = [
        ['Publicerade prompts', stats.published_prompts, 'creator-content.html'],
        ['Publicerade paket', stats.published_packages, 'creator-packages.html'],
        ['Under granskning', stats.in_review, 'creator-content.html'],
        ['Utkast', stats.drafts, 'creator-content.html']
    ];

    container.innerHTML = '';
    cells.forEach(([label, value, href]) => {
        const link = document.createElement('a');
        link.className = 'overview-stat';
        link.href = href;

        const number = document.createElement('strong');
        number.textContent = String(value ?? 0);
        const text = document.createElement('span');
        text.textContent = label;

        link.append(number, text);
        container.appendChild(link);
    });
    section.hidden = false;
}

async function load() {
    const statusEl = el('[data-overview-status]');
    statusEl.textContent = 'Laddar...';

    const { data, error } = await supabase.rpc('get_my_creator_overview');
    if (error) {
        statusEl.textContent = `Kunde inte ladda översikten: ${error.message}`;
        statusEl.classList.add('is-error');
        return;
    }

    renderChecklist(data.checklist);
    renderNeedsAction(data.needs_action || []);
    renderRecent(data.recent || []);
    renderStats(data.stats || {});

    const pending = (data.needs_action || []).length;
    statusEl.textContent = pending
        ? `${pending} sak${pending === 1 ? '' : 'er'} väntar på dig.`
        : 'Inget väntar på dig just nu.';
    el('[data-overview-content]').hidden = false;
}

async function init() {
    const statusEl = el('[data-overview-status]');
    if (!requireSupabaseConfig(statusEl)) return;

    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
        el('[data-overview-login-needed]').hidden = false;
        statusEl.hidden = true;
        return;
    }

    el('[data-overview-user-email]').textContent = session.user.email || '-';
    const greetingName = session.user.user_metadata?.display_name
        || session.user.email?.split('@')[0]
        || '';
    el('[data-overview-greeting]').textContent = greetingName
        ? `Hej ${greetingName}`
        : 'Mitt bibliotek';
    el('[data-overview-logout]').addEventListener('click', async () => {
        await supabase.auth.signOut();
        window.location.href = 'login.html';
    });

    await load();
}

init().catch((error) => {
    const statusEl = el('[data-overview-status]');
    if (statusEl) statusEl.textContent = error.message || 'Kunde inte ladda översikten.';
});
