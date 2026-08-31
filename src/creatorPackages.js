import { requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';
import { libraryAccessLabel, openPublicationLabel } from './creatorLibrary.js';

const STATUS_LABELS = { draft: 'Utkast', review: 'Under granskning', published: 'Publicerad', archived: 'Arkiverad' };
const TYPE_LABELS = {
    collection: 'Samling — användaren väljer själv vilken mall hen behöver',
    workflow: 'Workflow — stegen körs i ordning'
};
const MAX_ITEMS = 8;

function escapeHtml(value) {
    return String(value ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
}

function el(selector, root = document) {
    return root.querySelector(selector);
}

async function renderDraft(cardTemplate, itemTemplate, draft, ownPrompts) {
    const node = cardTemplate.content.firstElementChild.cloneNode(true);
    node.dataset.draftId = draft.id;
    el('[data-draft-title]', node).textContent = draft.title;
    el('[data-draft-summary]', node).textContent = draft.summary || '';
    el('[data-draft-access-badge]', node).textContent = draft.is_open_reference
        ? 'Från Open'
        : libraryAccessLabel({ visibility: draft.access_label === 'shared' ? 'workspace' : 'private' });
    const openBadge = el('[data-draft-open-badge]', node);
    const openLabel = draft.is_open_reference ? 'Följer Open' : openPublicationLabel(draft);
    openBadge.textContent = openLabel || '';
    openBadge.hidden = !openLabel;
    openBadge.dataset.status = draft.open_submission_state || '';

    // Redaktionell återkoppling, samma mönster som creatorContent.js.
    const reviewNote = el('[data-draft-review-note]', node);
    if (draft.review_note && ['changes_requested', 'rejected'].includes(draft.open_submission_state)) {
        reviewNote.textContent = draft.open_submission_state === 'rejected'
            ? `Avslogs: ${draft.review_note}`
            : `Skickades tillbaka: ${draft.review_note}`;
        reviewNote.hidden = false;
    }

    const itemRequest = draft.is_open_reference
        ? supabase.rpc('get_referenced_library_package', { p_draft_id: draft.id, p_context_keys: ['generell'] })
        : supabase.rpc('list_creator_package_draft_items', { p_draft_id: draft.id });
    const { data: items, error: itemsError } = await itemRequest;
    const itemList = itemsError ? [] : draft.is_open_reference
        ? (items || []).map((item) => ({
            title: item.item_title,
            summary: item.item_summary,
            content: item.item_prompt_text
        }))
        : items;

    if (draft.is_open_reference) {
        el('[data-draft-open-details]', node).hidden = true;
        const shareLink = el('[data-draft-share-link]', node);
        shareLink.href = draft.canonical_slug
            ? `promptbanken.html?package=${encodeURIComponent(draft.canonical_slug)}`
            : 'promptbanken.html';
        shareLink.textContent = 'Visa i Open';
    }

    if (itemsError) {
        const errorEl = el('[data-draft-error]', node);
        errorEl.textContent = `Kunde inte ladda prompts i paketet: ${itemsError.message}`;
        errorEl.hidden = false;
    }

    const countHint = el('[data-draft-count-hint]', node);
    countHint.textContent = `${itemList.length}/${MAX_ITEMS} prompts` + (itemList.length >= 3 && itemList.length <= 6 ? ' — lagom paket' : itemList.length < 3 ? ' — 3–6 prompts brukar vara ett lagom paket' : '');

    el('[data-draft-type-badge]', node).textContent =
        TYPE_LABELS[draft.package_type] || TYPE_LABELS.collection;

    // Ordningen skrivs med reorder_package_draft_items, som funnits sedan
    // delprojekt 3 men aldrig anropats från gränssnittet. För ett workflow
    // är ordningen hela innebörden.
    const moveItem = async (fromIndex, toIndex) => {
        const ordered = itemList.map((i) => i.content_item_id);
        const [moved] = ordered.splice(fromIndex, 1);
        ordered.splice(toIndex, 0, moved);
        const { error } = await supabase.rpc('reorder_package_draft_items', {
            p_draft_id: draft.id,
            p_ordered_ids: ordered
        });
        if (error) {
            const errorEl = el('[data-draft-error]', node);
            errorEl.textContent = error.message;
            errorEl.hidden = false;
            return;
        }
        await loadDrafts();
    };

    const itemsEl = el('[data-draft-items]', node);
    itemList.forEach((item, index) => {
        const row = itemTemplate.content.firstElementChild.cloneNode(true);
        row.dataset.itemContentItemId = item.content_item_id;
        el('[data-item-title]', row).textContent = item.title;
        if (!draft.is_open_reference && draft.status === 'draft') {
            const upBtn = el('[data-item-up-btn]', row);
            const downBtn = el('[data-item-down-btn]', row);
            upBtn.hidden = index === 0;
            downBtn.hidden = index === itemList.length - 1;
            upBtn.addEventListener('click', () => moveItem(index, index - 1));
            downBtn.addEventListener('click', () => moveItem(index, index + 1));

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

    // Förhandsgranskning: paketet som en användare skulle möta det.
    // Ingenting sparas, ingenting skickas.
    if (itemList.length) {
        const previewBtn = el('[data-draft-preview-btn]', node);
        const previewEl = el('[data-draft-preview]', node);
        previewBtn.hidden = false;
        previewBtn.addEventListener('click', () => {
            if (!previewEl.hidden) {
                previewEl.hidden = true;
                previewBtn.textContent = 'Öppna paket';
                return;
            }
            const heading = `<h3>${escapeHtml(draft.title)}</h3>` +
                (draft.summary ? `<p>${escapeHtml(draft.summary)}</p>` : '');
            const steps = itemList
                .map((item, index) => {
                    const label = draft.package_type === 'workflow'
                        ? `Steg ${index + 1}: ${item.title}`
                        : item.title;
                    return `<h4>${escapeHtml(label)}</h4>` +
                        (item.summary ? `<p>${escapeHtml(item.summary)}</p>` : '');
                })
                .join('');
            previewEl.innerHTML = heading + steps;
            previewEl.hidden = false;
            previewBtn.textContent = 'Dölj förhandsgranskning';
        });
    }

    if (!draft.is_open_reference && draft.status !== 'archived') {
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

        const consentGroup = el('[data-draft-consent-group]', node);
        const consentDistribution = el('[data-draft-consent-distribution]', node);
        const rightsAttested = el('[data-draft-rights-attested]', node);
        consentGroup.hidden = false;

        // Speglar RPC:ns regel: rättighetsintyget krävs om
        // distributionssamtycket är i.
        const syncSubmitEnabled = () => {
            submitBtn.disabled = consentDistribution.checked && !rightsAttested.checked;
        };
        [consentDistribution, rightsAttested].forEach((box) => {
            box.addEventListener('change', syncSubmitEnabled);
        });
        syncSubmitEnabled();

        submitBtn.hidden = draft.open_submission_state === 'review';
        submitBtn.addEventListener('click', async () => {
            errorEl.hidden = true;
            const { error } = await supabase.rpc('submit_creator_package_draft', {
                p_draft_id: draft.id,
                p_consent_distribution: consentDistribution.checked,
                p_rights_attested: rightsAttested.checked
            });
            if (error) {
                errorEl.textContent = error.message;
                errorEl.hidden = false;
                return;
            }
            await loadDrafts();
        });
    }

    if (draft.open_submission_state === 'review') {
        el('[data-draft-open-details]', node).open = true;
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
    const [
        { data: drafts, error: draftsError },
        { data: ownPrompts, error: promptsError },
        { data: libraryItems, error: libraryError },
        { data: referenceRows, error: referenceError },
        { data: catalogPackages, error: catalogError }
    ] = await Promise.all([
        supabase.rpc('list_my_creator_package_drafts'),
        supabase.rpc('list_my_package_eligible_prompts'),
        supabase.rpc('list_my_library_items'),
        supabase.from('creator_package_drafts')
            .select('id,library_ref_catalog_package_id')
            .not('library_ref_catalog_package_id', 'is', null),
        supabase.rpc('list_published_packages', {
            p_context_keys: ['generell'],
            p_include_creator_content: true
        })
    ]);

    if (draftsError || promptsError || libraryError || referenceError || catalogError) {
        statusEl.textContent = `Kunde inte ladda paket: ${(draftsError || promptsError || libraryError || referenceError || catalogError).message}`;
        return;
    }

    const libraryById = new Map((libraryItems || [])
        .filter((item) => item.kind === 'package')
        .map((item) => [item.subject_id, item]));
    const referenceById = new Map((referenceRows || []).map((row) => [row.id, row]));
    const catalogById = new Map((catalogPackages || []).map((pkg) => [pkg.id, pkg]));
    const mergedDrafts = drafts.map((draft) => {
        const reference = referenceById.get(draft.id);
        const canonical = reference ? catalogById.get(reference.library_ref_catalog_package_id) : null;
        return {
            ...draft,
            ...(libraryById.get(draft.id) || {}),
            is_open_reference: Boolean(reference),
            canonical_slug: canonical?.slug || null,
            title: canonical?.title || draft.title,
            summary: canonical?.summary || draft.summary,
            package_type: canonical?.package_type || draft.package_type
        };
    });

    statusEl.textContent = mergedDrafts.length ? '' : 'Du har inga paket i ditt bibliotek ännu.';
    listEl.innerHTML = '';
    for (const draft of mergedDrafts) {
        listEl.appendChild(await renderDraft(cardTemplate, itemTemplate, draft, ownPrompts));
    }
}

function registerNewDraftForm() {
    const titleInput = el('[data-new-draft-title]');
    const summaryInput = el('[data-new-draft-summary]');
    const errorEl = el('[data-new-draft-error]');

    el('[data-new-draft-btn]').addEventListener('click', async () => {
        errorEl.hidden = true;
        const selectedType = document.querySelector('[data-new-draft-type]:checked');
        const { error } = await supabase.rpc('upsert_creator_package_draft', {
            // null betyder nytt utkast. Måste skickas uttryckligen: parametern
            // har ingen default, och PostgREST matchar på namngivna argument —
            // utelämnad blir anropet en signatur som inte finns.
            p_draft_id: null,
            p_title: titleInput.value,
            p_summary: summaryInput.value,
            p_package_type: selectedType ? selectedType.value : 'collection'
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
