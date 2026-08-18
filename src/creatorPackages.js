import { requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const STATUS_LABELS = { draft: 'Utkast', review: 'Under granskning', published: 'Publicerad', archived: 'Arkiverad' };
const MAX_ITEMS = 8;

function el(selector, root = document) {
    return root.querySelector(selector);
}

async function renderDraft(cardTemplate, itemTemplate, draft, ownPrompts) {
    const node = cardTemplate.content.firstElementChild.cloneNode(true);
    node.dataset.draftId = draft.id;
    el('[data-draft-title]', node).textContent = draft.title;
    el('[data-draft-summary]', node).textContent = draft.summary || '';
    el('[data-draft-status-badge]', node).textContent = STATUS_LABELS[draft.status] || draft.status;

    const { data: items, error: itemsError } = await supabase.rpc('list_creator_package_draft_items', { p_draft_id: draft.id });
    const itemList = itemsError ? [] : items;

    if (itemsError) {
        const errorEl = el('[data-draft-error]', node);
        errorEl.textContent = `Kunde inte ladda prompts i paketet: ${itemsError.message}`;
        errorEl.hidden = false;
    }

    const countHint = el('[data-draft-count-hint]', node);
    countHint.textContent = `${itemList.length}/${MAX_ITEMS} prompts` + (itemList.length >= 3 && itemList.length <= 6 ? ' — lagom paket' : itemList.length < 3 ? ' — 3–6 prompts brukar vara ett lagom paket' : '');

    const itemsEl = el('[data-draft-items]', node);
    itemList.forEach((item) => {
        const row = itemTemplate.content.firstElementChild.cloneNode(true);
        row.dataset.itemContentItemId = item.content_item_id;
        el('[data-item-title]', row).textContent = item.title;
        if (draft.status === 'draft') {
            const removeBtn = el('[data-item-remove-btn]', row);
            removeBtn.hidden = false;
            removeBtn.addEventListener('click', async () => {
                const { error } = await supabase.rpc('remove_prompt_from_package_draft', {
                    p_draft_id: draft.id,
                    p_content_item_id: item.content_item_id
                });
                if (error) { alert(error.message); return; }
                await loadDrafts();
            });
        }
        itemsEl.appendChild(row);
    });

    if (draft.status === 'draft') {
        const addRow = el('[data-draft-add-row]', node);
        const submitBtn = el('[data-draft-submit-btn]', node);
        const errorEl = el('[data-draft-error]', node);

        if (itemList.length < MAX_ITEMS) {
            addRow.hidden = false;
            const select = el('[data-draft-add-select]', node);
            const addedIds = new Set(itemList.map((i) => i.content_item_id));
            ownPrompts.filter((p) => !addedIds.has(p.id)).forEach((p) => {
                const option = document.createElement('option');
                option.value = p.id;
                option.textContent = `${p.title} (${STATUS_LABELS[p.status] || p.status})`;
                select.appendChild(option);
            });
            el('[data-draft-add-btn]', node).addEventListener('click', async () => {
                if (!select.value) return;
                const { error } = await supabase.rpc('add_prompt_to_package_draft', {
                    p_draft_id: draft.id,
                    p_content_item_id: select.value,
                    p_position: itemList.length
                });
                if (error) { alert(error.message); return; }
                await loadDrafts();
            });
        }

        submitBtn.hidden = false;
        submitBtn.addEventListener('click', async () => {
            errorEl.hidden = true;
            const { error } = await supabase.rpc('submit_creator_package_draft', { p_draft_id: draft.id });
            if (error) {
                errorEl.textContent = error.message;
                errorEl.hidden = false;
                return;
            }
            await loadDrafts();
        });
    } else if (draft.status === 'review') {
        const withdrawBtn = el('[data-draft-withdraw-btn]', node);
        withdrawBtn.hidden = false;
        withdrawBtn.addEventListener('click', async () => {
            const { error } = await supabase.rpc('withdraw_creator_package_draft', { p_draft_id: draft.id });
            if (error) { alert(error.message); return; }
            await loadDrafts();
        });
    }

    return node;
}

async function loadDrafts() {
    const statusEl = el('[data-creator-packages-status]');
    const listEl = el('[data-draft-list]');
    const cardTemplate = el('[data-draft-row-template]');
    const itemTemplate = el('[data-draft-item-template]');

    statusEl.textContent = 'Laddar...';
    const [{ data: drafts, error: draftsError }, { data: ownPrompts, error: promptsError }] = await Promise.all([
        supabase.rpc('list_my_creator_package_drafts'),
        supabase.rpc('list_my_creator_prompts')
    ]);

    if (draftsError || promptsError) {
        statusEl.textContent = `Kunde inte ladda paket: ${(draftsError || promptsError).message}`;
        return;
    }

    statusEl.textContent = drafts.length ? '' : 'Du har inga paket-utkast ännu.';
    listEl.innerHTML = '';
    for (const draft of drafts) {
        listEl.appendChild(await renderDraft(cardTemplate, itemTemplate, draft, ownPrompts));
    }
}

function registerNewDraftForm() {
    const titleInput = el('[data-new-draft-title]');
    const summaryInput = el('[data-new-draft-summary]');
    const errorEl = el('[data-new-draft-error]');

    el('[data-new-draft-btn]').addEventListener('click', async () => {
        errorEl.hidden = true;
        const { error } = await supabase.rpc('upsert_creator_package_draft', {
            p_title: titleInput.value,
            p_summary: summaryInput.value
        });
        if (error) {
            errorEl.textContent = error.message;
            errorEl.hidden = false;
            return;
        }
        titleInput.value = '';
        summaryInput.value = '';
        await loadDrafts();
    });
}

async function init() {
    const statusEl = el('[data-creator-packages-status]');
    if (!requireSupabaseConfig(statusEl)) return;

    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
        el('[data-creator-packages-login-needed]').hidden = false;
        el('[data-creator-packages-status]').hidden = true;
        return;
    }

    el('[data-creator-packages-user-email]').textContent = session.user.email || '-';
    el('[data-creator-packages-logout]').addEventListener('click', async () => {
        await supabase.auth.signOut();
        window.location.href = 'login.html';
    });

    el('[data-creator-packages-content]').hidden = false;
    registerNewDraftForm();
    await loadDrafts();
}

init();
