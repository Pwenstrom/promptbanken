import { requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';
import { wireConfirmButton } from './confirmAction.js';

const STATUS_LABELS = { draft: 'Utkast', review: 'Under granskning', published: 'Publicerad', archived: 'Arkiverad' };

function el(selector, root = document) {
    return root.querySelector(selector);
}

function renderRow(template, prompt) {
    const node = template.content.firstElementChild.cloneNode(true);
    node.dataset.rowContentItemId = prompt.id;
    el('[data-row-title]', node).textContent = prompt.title;
    el('[data-row-summary]', node).textContent = prompt.summary || '';
    const statusBadge = el('[data-row-status-badge]', node);
    statusBadge.textContent = STATUS_LABELS[prompt.status] || prompt.status;
    statusBadge.dataset.status = prompt.status;

    // Redaktionell återkoppling. Utan den vet creatorn inte varför prompten
    // kom tillbaka, och "Begär ändring" i adminvyn blir en återvändsgränd.
    const reviewNote = el('[data-row-review-note]', node);
    if (prompt.review_note && (prompt.status === 'draft' || prompt.status === 'archived')) {
        reviewNote.textContent = prompt.status === 'archived'
            ? `Avslogs: ${prompt.review_note}`
            : `Skickades tillbaka: ${prompt.review_note}`;
        reviewNote.hidden = false;
    }

    const submitForm = el('[data-row-submit-form]', node);
    const withdrawBtn = el('[data-row-withdraw-btn]', node);
    const editForm = el('[data-row-edit-form]', node);

    // Redigering. Utan den blir "Begär ändring" en återvändsgränd:
    // creatorn läser motiveringen men kan inte åtgärda något.
    if (prompt.status === 'draft') {
        const editBtn = el('[data-row-edit-btn]', node);
        const saveBtn = el('[data-row-save-btn]', node);
        const cancelBtn = el('[data-row-cancel-btn]', node);
        const titleInput = el('[data-row-edit-title]', node);
        const contentInput = el('[data-row-edit-content]', node);
        const summaryInput = el('[data-row-edit-summary]', node);
        const categoryInput = el('[data-row-edit-category]', node);
        const editError = el('[data-row-error]', node);

        const openEditor = (open) => {
            editForm.hidden = !open;
            editBtn.hidden = open;
            el('[data-row-submit-btn]', node).hidden = open;
        };

        editBtn.addEventListener('click', () => {
            titleInput.value = prompt.title || '';
            contentInput.value = prompt.content || '';
            summaryInput.value = prompt.summary || '';
            categoryInput.value = prompt.category || '';
            openEditor(true);
        });

        cancelBtn.addEventListener('click', () => openEditor(false));

        saveBtn.addEventListener('click', async () => {
            editError.hidden = true;
            saveBtn.disabled = true;
            const { error } = await supabase.rpc('update_my_creator_prompt', {
                p_content_item_id: prompt.id,
                p_title: titleInput.value,
                p_content: contentInput.value,
                p_summary: summaryInput.value,
                p_category: categoryInput.value
            });
            saveBtn.disabled = false;
            if (error) {
                editError.textContent = error.message;
                editError.hidden = false;
                return;
            }
            await loadPrompts();
        });
    }

    if (prompt.status === 'draft') {
        submitForm.hidden = false;
        const consentShared = el('[data-row-consent-shared]', node);
        const consentReusable = el('[data-row-consent-reusable]', node);
        const consentDistribution = el('[data-row-consent-distribution]', node);
        const rightsAttested = el('[data-row-rights-attested]', node);
        const submitBtn = el('[data-row-submit-btn]', node);
        const errorEl = el('[data-row-error]', node);

        // Rättighetsintyget krävs bara om distributionssamtycket är i.
        // RPC:n vägrar annars, men att spegla regeln här sparar creatorn
        // ett misslyckat inskick.
        const syncSubmitEnabled = () => {
            const rightsMissing = consentDistribution.checked && !rightsAttested.checked;
            submitBtn.disabled = !consentShared.checked || rightsMissing;
        };
        [consentShared, consentDistribution, rightsAttested].forEach((box) => {
            box.addEventListener('change', syncSubmitEnabled);
        });
        syncSubmitEnabled();

        submitBtn.addEventListener('click', async () => {
            errorEl.hidden = true;
            const { error } = await supabase.rpc('submit_creator_prompt', {
                p_content_item_id: prompt.id,
                p_consent_shared: consentShared.checked,
                p_consent_reusable: consentReusable.checked,
                p_consent_distribution: consentDistribution.checked,
                p_rights_attested: rightsAttested.checked
            });
            if (error) {
                errorEl.textContent = error.message;
                errorEl.hidden = false;
                return;
            }
            await loadPrompts();
        });
    } else if (prompt.status === 'review') {
        withdrawBtn.hidden = false;
        withdrawBtn.addEventListener('click', async () => {
            const { error } = await supabase.rpc('withdraw_creator_prompt', { p_content_item_id: prompt.id });
            if (error) {
                alert(error.message);
                return;
            }
            await loadPrompts();
        });
    }

    // Radering. Under granskning måste dras tillbaka först och publicerat
    // ligger i öppna katalogen -- RPC:n vägrar båda, så knappen visas inte
    // heller för dem.
    if (prompt.status === 'draft' || prompt.status === 'archived') {
        const deleteBtn = el('[data-row-delete-btn]', node);
        deleteBtn.hidden = false;
        wireConfirmButton(deleteBtn, {
            onConfirm: async () => {
                const { error } = await supabase.rpc('delete_my_creator_prompt', {
                    p_content_item_id: prompt.id
                });
                if (error) {
                    alert(error.message);
                    return;
                }
                await loadPrompts();
            }
        });
    }

    return node;
}

// Följda och kopierade katalogprompts. De ligger i module='valvet' och
// syns därför inte i list_my_creator_prompts (module='kommun'). Utan den
// här sektionen fanns "lägg till i mitt bibliotek" men ingen väg tillbaka.
async function loadLibrary() {
    const section = el('[data-library-section]');
    const list = el('[data-library-list]');
    const template = el('[data-library-row-template]');
    const statusEl = el('[data-library-status]');

    const { data, error } = await supabase.rpc('list_my_library_prompts');
    if (error) {
        section.hidden = false;
        statusEl.hidden = false;
        statusEl.textContent = `Kunde inte ladda biblioteket: ${error.message}`;
        return;
    }

    if (!data.length) {
        section.hidden = true;
        return;
    }

    list.innerHTML = '';
    data.forEach((item) => {
        const node = template.content.firstElementChild.cloneNode(true);
        node.dataset.libraryItemId = item.id;
        el('[data-library-title]', node).textContent = item.title;
        el('[data-library-summary]', node).textContent = item.summary || '';
        el('[data-library-kind-badge]', node).textContent =
            item.is_library_reference ? 'Följer' : 'Egen kopia';

        const errorEl = el('[data-library-error]', node);
        const removeBtn = el('[data-library-remove-btn]', node);
        removeBtn.textContent = item.is_library_reference ? 'Sluta följa' : 'Ta bort';

        wireConfirmButton(removeBtn, {
            confirmLabel: item.is_library_reference ? 'Bekräfta?' : 'Bekräfta radering?',
            onConfirm: async () => {
                errorEl.hidden = true;
                const { error: removeError } = await supabase.rpc('delete_my_creator_prompt', {
                    p_content_item_id: item.id
                });
                if (removeError) {
                    errorEl.textContent = removeError.message;
                    errorEl.hidden = false;
                    return;
                }
                await loadLibrary();
            }
        });

        list.appendChild(node);
    });

    statusEl.hidden = true;
    section.hidden = false;
}

async function loadPrompts() {
    const statusEl = el('[data-creator-content-status]');
    const listEl = el('[data-creator-content-list]');
    const template = el('[data-creator-content-row-template]');

    statusEl.textContent = 'Laddar...';
    const { data, error } = await supabase.rpc('list_my_creator_prompts');
    if (error) {
        statusEl.textContent = `Kunde inte ladda dina prompts: ${error.message}`;
        return;
    }

    statusEl.textContent = data.length ? '' : 'Du har inga prompts i din personliga arbetsyta ännu.';
    listEl.innerHTML = '';
    data.forEach((prompt) => listEl.appendChild(renderRow(template, prompt)));
    listEl.hidden = false;
}

// Plockar en titel och en sammanfattning ur en importerad .md-fil så att
// "Skapa ny prompt" kan förifyllas. Enkel heuristik, inte en full
// Markdown-parser: filens första "# rubrik" blir titel (annars filnamnet
// utan ändelse), och den första textraden efter den blir sammanfattning.
function parseMarkdownPrompt(rawText, fallbackTitle) {
    const lines = rawText.replace(/\r\n/g, '\n').split('\n');
    let title = fallbackTitle;
    const headingIndex = lines.findIndex((line) => /^#\s+\S/.test(line));
    if (headingIndex !== -1) {
        title = lines[headingIndex].replace(/^#\s+/, '').trim();
        lines.splice(headingIndex, 1);
    }

    const content = lines.join('\n').trim();
    const firstParagraph = lines.find((line) => line.trim().length > 0) || '';
    const summary = firstParagraph.replace(/^#+\s*/, '').trim().slice(0, 500);

    return { title, content, summary };
}

function registerNewPromptForm() {
    const titleInput = el('[data-new-prompt-title]');
    const contentInput = el('[data-new-prompt-content]');
    const summaryInput = el('[data-new-prompt-summary]');
    const categoryInput = el('[data-new-prompt-category]');
    const errorEl = el('[data-new-prompt-error]');
    const btn = el('[data-new-prompt-btn]');

    const dropzone = el('[data-new-prompt-dropzone]');
    const browseLink = el('[data-new-prompt-browse]');
    const fileInput = el('[data-new-prompt-file]');
    const importChip = el('[data-new-prompt-import-chip]');
    const importFilename = el('[data-new-prompt-import-filename]');
    const importClearBtn = el('[data-new-prompt-import-clear]');
    const importErrorEl = el('[data-new-prompt-import-error]');

    const resetImportChip = () => {
        importChip.hidden = true;
        importFilename.textContent = '';
    };

    const showImportError = (message) => {
        importErrorEl.textContent = message;
        importErrorEl.hidden = false;
    };

    const importFile = (file) => {
        importErrorEl.hidden = true;
        if (!file) return;
        if (!/\.md$/i.test(file.name) && file.type !== 'text/markdown') {
            showImportError('Filen måste vara en .md-fil.');
            return;
        }

        const reader = new FileReader();
        reader.onerror = () => showImportError('Kunde inte läsa filen.');
        reader.onload = () => {
            const fallbackTitle = file.name.replace(/\.md$/i, '');
            const { title, content, summary } = parseMarkdownPrompt(String(reader.result || ''), fallbackTitle);
            titleInput.value = title;
            contentInput.value = content;
            summaryInput.value = summary;
            importFilename.textContent = `${file.name} importerad`;
            importChip.hidden = false;
        };
        reader.readAsText(file);
    };

    dropzone.addEventListener('click', () => fileInput.click());
    dropzone.addEventListener('keydown', (event) => {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            fileInput.click();
        }
    });
    browseLink.addEventListener('click', (event) => {
        event.stopPropagation();
        fileInput.click();
    });

    fileInput.addEventListener('change', () => {
        importFile(fileInput.files[0]);
        fileInput.value = '';
    });

    ['dragenter', 'dragover'].forEach((eventName) => {
        dropzone.addEventListener(eventName, (event) => {
            event.preventDefault();
            dropzone.classList.add('is-dragover');
        });
    });
    ['dragleave', 'dragend', 'drop'].forEach((eventName) => {
        dropzone.addEventListener(eventName, (event) => {
            event.preventDefault();
            dropzone.classList.remove('is-dragover');
        });
    });
    dropzone.addEventListener('drop', (event) => {
        const file = event.dataTransfer && event.dataTransfer.files && event.dataTransfer.files[0];
        importFile(file);
    });

    importClearBtn.addEventListener('click', resetImportChip);

    btn.addEventListener('click', async () => {
        errorEl.hidden = true;
        btn.disabled = true;
        const { error } = await supabase.rpc('create_my_creator_prompt', {
            p_title: titleInput.value,
            p_content: contentInput.value,
            p_summary: summaryInput.value,
            p_category: categoryInput.value
        });
        btn.disabled = false;
        if (error) {
            errorEl.textContent = error.message;
            errorEl.hidden = false;
            return;
        }
        titleInput.value = '';
        contentInput.value = '';
        summaryInput.value = '';
        categoryInput.value = '';
        resetImportChip();
        await loadPrompts();
    });
}

async function init() {
    const statusEl = el('[data-creator-content-status]');
    if (!requireSupabaseConfig(statusEl)) return;

    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
        el('[data-creator-content-login-needed]').hidden = false;
        statusEl.hidden = true;
        return;
    }

    el('[data-creator-content-user-email]').textContent = session.user.email || '-';
    el('[data-creator-content-logout]').addEventListener('click', async () => {
        await supabase.auth.signOut();
        window.location.href = 'login.html';
    });

    el('[data-creator-content-new-prompt]').hidden = false;
    registerNewPromptForm();
    await loadPrompts();
    await loadLibrary();
}

init();
