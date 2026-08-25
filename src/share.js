// Den publika delningssidan.
//
// Anonym, ingen inloggning, ingen möjlighet att ändra något. Sidan sätter
// noindex i HTML:en — utan det vore en delningslänk i praktiken publicering.
//
// Se docs/superpowers/specs/2026-08-24-creator-ux-structure.md.

import { supabase } from './supabaseClient.js';

function el(selector, root = document) {
    return root.querySelector(selector);
}

function token() {
    return new URLSearchParams(window.location.search).get('s') || '';
}

function showGone(title, text) {
    el('[data-share-status]').hidden = true;
    el('[data-share-gone-title]').textContent = title;
    el('[data-share-gone-text]').textContent = text;
    el('[data-share-gone]').hidden = false;
}

function renderPrompt(content, bodyEl) {
    const pre = document.createElement('pre');
    pre.className = 'share-prompt-text';
    pre.textContent = content.prompt_text || '';
    bodyEl.appendChild(pre);

    const examples = Array.isArray(content.security_examples) ? content.security_examples : [];
    if (examples.length) {
        const heading = document.createElement('h2');
        heading.textContent = 'Tänk på att inte klistra in';
        const list = document.createElement('ul');
        list.className = 'share-security';
        examples.forEach((item) => {
            const li = document.createElement('li');
            li.textContent = item;
            list.append(li);
        });
        bodyEl.append(heading, list);
    }

    return content.prompt_text || '';
}

function renderPackage(content, bodyEl) {
    if (content.intro_text) {
        const intro = document.createElement('p');
        intro.textContent = content.intro_text;
        bodyEl.appendChild(intro);
    }

    const items = Array.isArray(content.items) ? content.items : [];
    const isWorkflow = content.package_type === 'workflow';
    const parts = [];

    items.forEach((item, index) => {
        const heading = document.createElement('h2');
        heading.textContent = isWorkflow
            ? `Steg ${index + 1}: ${item.title}`
            : item.title;

        const pre = document.createElement('pre');
        pre.className = 'share-prompt-text';
        pre.textContent = item.prompt_text || '';

        bodyEl.append(heading);
        if (item.summary) {
            const summary = document.createElement('p');
            summary.textContent = item.summary;
            bodyEl.append(summary);
        }
        bodyEl.append(pre);

        parts.push(`## ${heading.textContent}\n\n${item.prompt_text || ''}`);
    });

    return parts.join('\n\n');
}

async function init() {
    const statusEl = el('[data-share-status]');
    const shareToken = token();

    if (!shareToken) {
        showGone('Länken är ofullständig', 'Adressen saknar delningens kod. Be den som skickade länken om en ny.');
        return;
    }

    const { data, error } = await supabase.rpc('get_shared_content', { p_token: shareToken });

    if (error) {
        statusEl.textContent = `Kunde inte hämta innehållet: ${error.message}`;
        statusEl.classList.add('is-error');
        return;
    }

    if (data.state === 'not_found') {
        showGone('Länken fungerar inte', 'Delningen finns inte. Kontrollera att hela adressen kom med.');
        return;
    }

    if (data.state === 'expired') {
        showGone('Den här delningen har upphört', 'Den som delade innehållet har avslutat länken, eller så har den gått ut.');
        return;
    }

    const content = data.content || {};
    const bodyEl = el('[data-share-body]');

    el('[data-share-title]').textContent = content.title || '';
    el('[data-share-summary]').textContent = content.summary || '';

    const meta = [];
    if (content.kind === 'package') {
        meta.push(content.package_type === 'workflow' ? 'Workflow' : 'Samling');
        meta.push(`${(content.items || []).length} steg`);
    }
    if (content.audience_label) meta.push(content.audience_label);
    if (data.pinned) meta.push('Låst version');
    el('[data-share-meta]').textContent = meta.join(' · ');

    if (data.creator && data.creator.display_name) {
        el('[data-share-creator-name]').textContent = data.creator.display_name;
        el('[data-share-creator-link]').href = `/creator/${data.creator.slug}/`;
        el('[data-share-byline]').hidden = false;
    }

    const copyText = content.kind === 'package'
        ? renderPackage(content, bodyEl)
        : renderPrompt(content, bodyEl);

    const copyBtn = el('[data-share-copy]');
    copyBtn.addEventListener('click', async () => {
        try {
            await navigator.clipboard.writeText(copyText);
            copyBtn.textContent = 'Kopierad';
            setTimeout(() => { copyBtn.textContent = 'Kopiera prompten'; }, 2000);
            // Räknas dygnsvis. Ett misslyckat anrop får inte störa
            // kopieringen, som redan lyckats.
            supabase.rpc('record_share_copy', { p_token: shareToken }).catch(() => {});
        } catch {
            copyBtn.textContent = 'Kunde inte kopiera';
        }
    });

    statusEl.hidden = true;
    el('[data-share-content]').hidden = false;
    document.title = `${content.title || 'Delad prompt'} | Promptbanken`;
}

init().catch((error) => {
    const statusEl = el('[data-share-status]');
    if (statusEl) statusEl.textContent = error.message || 'Kunde inte hämta innehållet.';
});
