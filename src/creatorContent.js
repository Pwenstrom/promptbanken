import { supabase } from './supabaseClient.js';

const STATUS_LABELS = { draft: 'Utkast', review: 'Under granskning', published: 'Publicerad', archived: 'Arkiverad' };

function el(selector, root = document) {
    return root.querySelector(selector);
}

function renderRow(template, prompt) {
    const node = template.content.firstElementChild.cloneNode(true);
    node.dataset.rowContentItemId = prompt.id;
    el('[data-row-title]', node).textContent = prompt.title;
    el('[data-row-summary]', node).textContent = prompt.summary || '';
    el('[data-row-status-badge]', node).textContent = STATUS_LABELS[prompt.status] || prompt.status;

    const submitForm = el('[data-row-submit-form]', node);
    const withdrawBtn = el('[data-row-withdraw-btn]', node);

    if (prompt.status === 'draft') {
        submitForm.hidden = false;
        const consentShared = el('[data-row-consent-shared]', node);
        const consentReusable = el('[data-row-consent-reusable]', node);
        const submitBtn = el('[data-row-submit-btn]', node);
        const errorEl = el('[data-row-error]', node);

        const syncSubmitEnabled = () => { submitBtn.disabled = !consentShared.checked; };
        consentShared.addEventListener('change', syncSubmitEnabled);
        syncSubmitEnabled();

        submitBtn.addEventListener('click', async () => {
            errorEl.hidden = true;
            const { error } = await supabase.rpc('submit_creator_prompt', {
                p_content_item_id: prompt.id,
                p_consent_shared: consentShared.checked,
                p_consent_reusable: consentReusable.checked
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

    return node;
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

    statusEl.textContent = data.length ? '' : 'Du har inga prompts i din personlig arbetsyta ännu.';
    listEl.innerHTML = '';
    data.forEach((prompt) => listEl.appendChild(renderRow(template, prompt)));
    listEl.hidden = false;
}

async function init() {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
        el('[data-creator-content-login-needed]').hidden = false;
        el('[data-creator-content-status]').hidden = true;
        return;
    }

    el('[data-creator-content-user-email]').textContent = session.user.email || '-';
    el('[data-creator-content-logout]').addEventListener('click', async () => {
        await supabase.auth.signOut();
        window.location.href = 'login.html';
    });

    await loadPrompts();
}

init();
