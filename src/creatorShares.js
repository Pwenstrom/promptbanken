// Creatorns delningar.
//
// Bara publicerat innehåll går att dela — regeln sitter i RPC:n, och den
// här vyn erbjuder helt enkelt inget annat i rullistan.
//
// Se docs/superpowers/specs/2026-08-24-creator-ux-structure.md.

import { requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const SHARE_BASE = `${window.location.origin}/delning/?s=`;

function el(selector, root = document) {
    return root.querySelector(selector);
}

function formatDate(value) {
    if (!value) return 'tills vidare';
    return new Date(value).toLocaleDateString('sv-SE');
}

async function copyToClipboard(text, button, doneLabel = 'Kopierad') {
    const original = button.textContent;
    try {
        await navigator.clipboard.writeText(text);
        button.textContent = doneLabel;
    } catch {
        button.textContent = 'Kunde inte kopiera';
    }
    setTimeout(() => { button.textContent = original; }, 2000);
}

// Rullistan visar allt eget delbart innehåll -- publicerat OCH eget
// opublicerat. list_my_shareable_content returnerar rätt subject_id för
// respektive kind (katalog-id för publicerat, content_items/draft-id för
// opublicerat).
async function loadSubjects() {
    const select = el('[data-share-subject]');
    const { data, error } = await supabase.rpc('list_my_shareable_content');

    select.innerHTML = '';
    if (error || !data || !data.length) {
        const option = document.createElement('option');
        option.textContent = 'Du har inget att dela än';
        option.value = '';
        select.appendChild(option);
        return;
    }

    data.forEach((item) => {
        const option = document.createElement('option');
        option.value = `${item.kind}:${item.subject_id}`;
        const kindLabel = item.kind.startsWith('package') ? 'Paket' : 'Prompt';
        option.textContent = `${kindLabel} (${item.status_label}): ${item.title}`;
        option.dataset.kind = item.kind;
        option.dataset.subjectId = item.subject_id;
        select.appendChild(option);
    });
}

function expiryValue() {
    const choice = el('[data-share-expiry]').value;
    if (choice === 'never') return null;
    if (choice === 'custom') {
        const raw = el('[data-share-custom-date]').value;
        return raw ? new Date(`${raw}T23:59:59`).toISOString() : null;
    }
    const days = Number(choice);
    return new Date(Date.now() + days * 86400000).toISOString();
}

function renderRow(share, template, container) {
    const node = template.content.firstElementChild.cloneNode(true);
    const url = SHARE_BASE + share.token;
    const errorEl = el('[data-row-error]', node);

    el('[data-row-label]', node).textContent = share.label || share.title || 'Delning';

    const meta = [
        share.subject_type === 'package' ? 'Paket' : 'Prompt',
        share.pinned ? 'Låst version' : 'Följer senaste',
        share.revoked_at
            ? `Avslutad ${formatDate(share.revoked_at)}`
            : `Giltig till ${formatDate(share.expires_at)}`
    ];
    el('[data-row-meta]', node).textContent = meta.join(' · ');
    el('[data-row-url]', node).textContent = url;

    if (share.subject_type === 'draft_prompt' || share.subject_type === 'package_draft') {
        const warning = document.createElement('p');
        warning.className = 'mp-hint';
        warning.textContent = 'Detta innehåll är inte granskat av Promptbanken än.';
        node.querySelector('.share-row-main').appendChild(warning);
    }
    el('[data-row-views]', node).textContent = share.views ?? 0;
    el('[data-row-copies]', node).textContent = share.copies ?? 0;

    const copyBtn = el('[data-row-copy-btn]', node);
    copyBtn.addEventListener('click', () => copyToClipboard(url, copyBtn));

    const extendBtn = el('[data-row-extend-btn]', node);
    const revokeBtn = el('[data-row-revoke-btn]', node);

    if (!share.is_active) {
        extendBtn.hidden = true;
        revokeBtn.hidden = true;
    } else {
        extendBtn.addEventListener('click', async () => {
            errorEl.hidden = true;
            const base = share.expires_at ? new Date(share.expires_at).getTime() : Date.now();
            const next = new Date(Math.max(base, Date.now()) + 30 * 86400000).toISOString();
            const { error } = await supabase.rpc('extend_creator_share', {
                p_share_id: share.id,
                p_expires_at: next
            });
            if (error) {
                errorEl.textContent = error.message;
                errorEl.hidden = false;
                return;
            }
            await loadShares();
        });

        // Avsluta kräver ett andra klick i knappen själv, ingen modal.
        let armed = false;
        revokeBtn.addEventListener('click', async () => {
            if (!armed) {
                armed = true;
                revokeBtn.textContent = 'Säker?';
                setTimeout(() => {
                    armed = false;
                    revokeBtn.textContent = 'Avsluta';
                }, 4000);
                return;
            }
            errorEl.hidden = true;
            const { error } = await supabase.rpc('revoke_creator_share', { p_share_id: share.id });
            if (error) {
                errorEl.textContent = error.message;
                errorEl.hidden = false;
                return;
            }
            await loadShares();
        });
    }

    container.appendChild(node);
}

async function loadShares() {
    const statusEl = el('[data-shares-status]');
    const template = el('[data-share-row-template]');
    const activeEl = el('[data-shares-active]');
    const endedEl = el('[data-shares-ended]');

    statusEl.textContent = 'Laddar...';
    const { data, error } = await supabase.rpc('list_my_creator_shares');

    if (error) {
        statusEl.textContent = `Kunde inte ladda delningar: ${error.message}`;
        statusEl.classList.add('is-error');
        return;
    }

    const active = data.filter((s) => s.is_active);
    const ended = data.filter((s) => !s.is_active);

    activeEl.innerHTML = '';
    endedEl.innerHTML = '';
    active.forEach((s) => renderRow(s, template, activeEl));
    ended.forEach((s) => renderRow(s, template, endedEl));

    el('[data-shares-active-empty]').hidden = active.length > 0;
    el('[data-shares-ended-section]').hidden = ended.length === 0;
    statusEl.textContent = active.length
        ? `${active.length} aktiv${active.length === 1 ? '' : 'a'} delning${active.length === 1 ? '' : 'ar'}.`
        : '';
}

function registerCreateForm() {
    el('[data-share-expiry]').addEventListener('change', (event) => {
        el('[data-share-custom-date-wrap]').hidden = event.target.value !== 'custom';
    });

    el('[data-share-create-btn]').addEventListener('click', async () => {
        const errorEl = el('[data-share-create-error]');
        errorEl.hidden = true;

        const select = el('[data-share-subject]');
        const option = select.selectedOptions[0];
        if (!option || !option.value) {
            errorEl.textContent = 'Välj något att dela först.';
            errorEl.hidden = false;
            return;
        }

        const { kind, subjectId } = option.dataset;

        const pinned = el('[data-share-version]:checked')?.value === 'pinned'
            || document.querySelector('[data-share-version][value="pinned"]')?.checked;

        const { data, error } = await supabase.rpc('create_creator_share', {
            p_subject_type: kind,
            p_subject_id: subjectId,
            p_pin_version: Boolean(pinned),
            p_expires_at: expiryValue(),
            p_label: el('[data-share-label]').value
        });

        if (error) {
            errorEl.textContent = error.message;
            errorEl.hidden = false;
            return;
        }

        const url = SHARE_BASE + data.token;
        el('[data-share-created-url]').textContent = url;
        el('[data-share-created]').hidden = false;
        const copyBtn = el('[data-share-created-copy]');
        copyBtn.onclick = () => copyToClipboard(url, copyBtn);

        el('[data-share-label]').value = '';
        await loadShares();
    });
}

async function init() {
    const statusEl = el('[data-shares-status]');
    if (!requireSupabaseConfig(statusEl)) return;

    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
        el('[data-shares-login-needed]').hidden = false;
        statusEl.hidden = true;
        return;
    }

    el('[data-shares-user-email]').textContent = session.user.email || '-';
    el('[data-shares-logout]').addEventListener('click', async () => {
        await supabase.auth.signOut();
        window.location.href = 'login.html';
    });

    el('[data-shares-content]').hidden = false;
    registerCreateForm();
    await loadSubjects();
    await loadShares();
}

init().catch((error) => {
    const statusEl = el('[data-shares-status]');
    if (statusEl) statusEl.textContent = error.message || 'Kunde inte ladda delningar.';
});
