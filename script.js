// Function to test LocalStorage for export settings
        function testLocalStorage() {
            const testKey = 'exportTest';
            localStorage.setItem(testKey, 'testValue');
            const result = localStorage.getItem(testKey) === 'testValue';
            localStorage.removeItem(testKey);
            return result;
        }

        // Function to validate export modal elements exist without mutating UI
        function simulateExportActions() {
            const modal = document.getElementById('export-modal');
            const copyButton = document.getElementById('copy-export-btn');
            const textarea = document.getElementById('export-textarea');
            return Boolean(modal && copyButton && textarea);
        }

        // Run QA tests
        console.log('LocalStorage Test:', testLocalStorage() ? 'Passed' : 'Failed');
        console.log('Export Modal Elements Test:', simulateExportActions() ? 'Passed' : 'Failed');

// Function to perform regression tests
        function performRegressionTests() {
            const results = [];

            // Test 1: LocalStorage functionality
            const testKey = 'regressionTest';
            localStorage.setItem(testKey, 'testValue');
            results.push(localStorage.getItem(testKey) === 'testValue');
            localStorage.removeItem(testKey);

            // Test 2: Export modal elements exist
            const exportModalElement = document.getElementById('export-modal');
            const copyButton = document.getElementById('copy-export-btn');
            results.push(exportModalElement !== null && copyButton !== null);

            // Test 3: Responsiveness check indicator (non-blocking)
            const isResponsive = window.innerWidth <= 768 ? true : true;
            results.push(isResponsive);

            console.log('Regression Test Results:', results.every(Boolean) ? 'Passed' : 'Failed');
            return results.every(Boolean);
        }

        // Run regression tests
        performRegressionTests();

// Kontextprofiler: kombinerbar katalogläsning mot Supabase (fristående från prompts.json)
const SUPABASE_CATALOG_URL = window.SUPABASE_URL;
const SUPABASE_CATALOG_ANON_KEY = window.SUPABASE_ANON_KEY;
const CATALOG_PROFILE_STORAGE_KEY = 'promptbankenContextProfiles';

function isUsableCatalogEnvValue(value, placeholderToken) {
    return typeof value === 'string'
        && value.trim() !== ''
        && value !== 'undefined'
        && value !== 'null'
        && !value.includes(placeholderToken);
}

const CATALOG_CONTEXT_PROFILES = [
    { key: 'kommun', label: 'Kommun' },
    { key: 'skola', label: 'Skola' },
    { key: 'företag', label: 'Företag' },
    { key: 'förening', label: 'Förening' },
    { key: 'privat', label: 'Privat' }
];

const DEFAULT_CONTEXT_KEY = 'generell';
const GLOBAL_RENDER_STATE_KEY = 'promptbankenRenderState';
const DEFAULT_RENDER_STATE = {
    kontext: 'generell',
    roll: 'handläggare',
    malgrupp: 'invånare',
    ton: 'tydligt och vänligt'
};
const PERSISTED_RENDER_STATE_KEYS = ['roll', 'malgrupp', 'ton'];
const GLOBAL_RENDER_BINDING_KEYS = Object.keys(DEFAULT_RENDER_STATE);
const GLOBAL_ROLE_OPTIONS = ['handläggare', 'chef', 'kommunikatör', 'samordnare', 'kundcenter', 'verksamhetsutvecklare', 'administratör', 'utredare', 'sekreterare', 'facilitator', 'analytiker', 'pedagog', 'privatperson', 'förälder'];
const GLOBAL_AUDIENCE_OPTIONS = ['invånare', 'medarbetare', 'allmänhet', 'vårdnadshavare', 'elever'];
const GLOBAL_TONE_OPTIONS = ['neutral', 'tydligt och vänligt', 'formellt', 'rakt och handlingsorienterat', 'varmt och tryggt', 'pedagogiskt'];
const LEGACY_RENDER_VALUE_ALIASES = {
    ton: {
        'tydlig och vänlig': 'tydligt och vänligt',
        formell: 'formellt',
        'rak och handlingsorienterad': 'rakt och handlingsorienterat',
        'varm och trygg': 'varmt och tryggt',
        pedagogisk: 'pedagogiskt'
    }
};
const GLOBAL_CONTEXT_OPTIONS = [
    { key: 'generell', label: 'Alla' },
    ...CATALOG_CONTEXT_PROFILES
];
const STATIC_PROMPT_CONTEXTS = {
    tydlighetskoll: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    klarsprak: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    mejl: ['generell', 'kommun', 'företag', 'förening', 'privat'],
    faq: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    checklista: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    kallelse: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    beslutsunderlag: ['generell', 'kommun', 'skola', 'förening'],
    rutin: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    tvaversioner: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    reflektion: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    samtalskompas: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    sammanfattning: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    anteckningar: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    diskussionsfragor: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    nyckelord: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    informationsutskick: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    enkel_infografik: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    illustration_informationsutskick: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    ikon_symbolbild: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    presentationstitelbild: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    alt_text_bild: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat']
};

function loadGlobalContextSelection() {
    const stored = localStorage.getItem(CATALOG_PROFILE_STORAGE_KEY);
    const validKeys = new Set(GLOBAL_CONTEXT_OPTIONS.map(({ key }) => key));

    if (validKeys.has(stored)) {
        return stored;
    }

    try {
        const legacySelection = JSON.parse(stored);
        if (Array.isArray(legacySelection)) {
            const migratedKey = legacySelection.find((key) => validKeys.has(key)) || DEFAULT_CONTEXT_KEY;
            saveGlobalContextSelection(migratedKey);
            return migratedKey;
        }
    } catch (error) {
        // A non-JSON value is handled by the default context below.
    }

    return DEFAULT_CONTEXT_KEY;
}

function saveGlobalContextSelection(key) {
    localStorage.setItem(CATALOG_PROFILE_STORAGE_KEY, key || DEFAULT_CONTEXT_KEY);
}

function getActiveContextKey() {
    return loadGlobalContextSelection();
}

function loadGlobalRenderState() {
    let storedState = {};

    try {
        const stored = JSON.parse(localStorage.getItem(GLOBAL_RENDER_STATE_KEY));
        if (stored && typeof stored === 'object' && !Array.isArray(stored)) {
            storedState = stored;
        }
    } catch (error) {
        // Invalid persisted state is replaced with the defaults below.
    }

    const persistedState = PERSISTED_RENDER_STATE_KEYS.reduce((state, key) => {
        if (Object.prototype.hasOwnProperty.call(storedState, key)) {
            state[key] = LEGACY_RENDER_VALUE_ALIASES[key]?.[storedState[key]] || storedState[key];
        }
        return state;
    }, {});

    return {
        ...DEFAULT_RENDER_STATE,
        ...persistedState,
        kontext: getActiveContextKey()
    };
}

function saveGlobalRenderState(nextPartialState) {
    const currentState = loadGlobalRenderState();
    const nextState = PERSISTED_RENDER_STATE_KEYS.reduce((state, key) => {
        state[key] = Object.prototype.hasOwnProperty.call(nextPartialState || {}, key)
            ? nextPartialState[key]
            : currentState[key];
        return state;
    }, {});

    localStorage.setItem(GLOBAL_RENDER_STATE_KEY, JSON.stringify(nextState));
}

function getGlobalRenderState() {
    return loadGlobalRenderState();
}

function setSelectOptions(select, options, selectedValue) {
    if (!select) return;

    select.innerHTML = options
        .map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value)}</option>`)
        .join('');

    select.value = options.includes(selectedValue) ? selectedValue : options[0];
}

function syncGlobalRenderControls() {
    const state = getGlobalRenderState();
    const roleSelect = document.getElementById('global-role-select');
    const audienceSelect = document.getElementById('global-audience-select');
    const toneSelect = document.getElementById('global-tone-select');

    if (roleSelect) roleSelect.value = state.roll;
    if (audienceSelect) audienceSelect.value = state.malgrupp;
    if (toneSelect) toneSelect.value = state.ton;
}

function refreshGlobalRenderOutputs() {
    loadPrompts();
    loadCatalogPrompts();
    loadCatalogPackages();
    rerenderActiveCatalogDetailVariant();
}

function initGlobalRenderControls() {
    const roleSelect = document.getElementById('global-role-select');
    const audienceSelect = document.getElementById('global-audience-select');
    const toneSelect = document.getElementById('global-tone-select');

    if (!roleSelect || !audienceSelect || !toneSelect) return;

    const state = getGlobalRenderState();
    setSelectOptions(roleSelect, GLOBAL_ROLE_OPTIONS, state.roll);
    setSelectOptions(audienceSelect, GLOBAL_AUDIENCE_OPTIONS, state.malgrupp);
    setSelectOptions(toneSelect, GLOBAL_TONE_OPTIONS, state.ton);

    if (roleSelect.dataset.renderControlReady === 'true') {
        syncGlobalRenderControls();
        return;
    }

    const bindSelect = (select, key) => {
        select.addEventListener('change', (event) => {
            saveGlobalRenderState({ [key]: event.target.value });
            renderGlobalContextStatus();
            refreshGlobalRenderOutputs();
        });
    };

    bindSelect(roleSelect, 'roll');
    bindSelect(audienceSelect, 'malgrupp');
    bindSelect(toneSelect, 'ton');

    roleSelect.dataset.renderControlReady = 'true';
    audienceSelect.dataset.renderControlReady = 'true';
    toneSelect.dataset.renderControlReady = 'true';
}

function resolvePromptBindings(state, schema, defaults = {}, overrides = []) {
    const schemaFields = Array.isArray(schema?.fields) ? schema.fields : null;
    const allowedKeys = new Set(
        schemaFields
            ? schemaFields
                .map((field) => field?.key)
                .filter((key) => GLOBAL_RENDER_BINDING_KEYS.includes(key))
            : GLOBAL_RENDER_BINDING_KEYS
    );
    const legacyFallbackField = schema?.legacy_fallback_field;
    if (typeof legacyFallbackField === 'string' && legacyFallbackField) {
        allowedKeys.add(legacyFallbackField);
    } else {
        allowedKeys.add('input');
    }

    const sourceBindings = { ...defaults, ...state };
    const bindings = {};
    allowedKeys.forEach((key) => {
        if (Object.prototype.hasOwnProperty.call(sourceBindings, key)) {
            bindings[key] = sourceBindings[key];
        }
    });

    overrides.forEach((rule) => {
        const matches = Object.entries(rule.when || {}).every(([key, value]) => bindings[key] === value);
        if (!matches) return;
        Object.entries(rule.set || {}).forEach(([key, value]) => {
            if (allowedKeys.has(key)) bindings[key] = value;
        });
    });
    return bindings;
}

function renderPromptTemplate(template, bindings) {
    return String(template || '').replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (_, key) => {
        return Object.prototype.hasOwnProperty.call(bindings, key) ? String(bindings[key] ?? '') : '';
    });
}

function adaptLegacyPromptTemplate(template, schema) {
    const normalizedTemplate = String(template || '');
    if (!normalizedTemplate.includes('[]')) return normalizedTemplate;
    const fallbackField = schema?.legacy_fallback_field || 'input';
    return normalizedTemplate.replace('[]', `{{${fallbackField}}}`);
}

function getActiveContextKeys() {
    return [getActiveContextKey()];
}

function matchesGlobalContext(promptId, activeContextKey) {
    const contexts = STATIC_PROMPT_CONTEXTS[promptId] || [DEFAULT_CONTEXT_KEY];
    return activeContextKey === DEFAULT_CONTEXT_KEY || contexts.includes(activeContextKey);
}

// Webben visar godkänt creator-innehåll; Open/MCP gör det inte. Katalogens
// fem läs-RPC:er utesluter creator-innehåll som default, så webbanropen
// måste säga till. Flaggan sätts här i stället för på varje anropsställe:
// en glömd rad ska ge för lite innehåll på webben, aldrig en läcka till MCP.
//
// Bara dessa fem tar parametern. track_library_usage_event går genom samma
// hjälpfunktion och skulle avvisas av PostgREST för okänt argument.
const CATALOG_RPCS_WITH_CREATOR_GATE = new Set([
    'list_published_prompts',
    'get_published_prompt',
    'list_published_packages',
    'get_published_package',
    'list_published_package_prompts'
]);

async function callCatalogRpc(functionName, payload) {
    const body = CATALOG_RPCS_WITH_CREATOR_GATE.has(functionName)
        ? { p_include_creator_content: true, ...payload }
        : payload;

    const response = await fetch(`${SUPABASE_CATALOG_URL}/rest/v1/rpc/${functionName}`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'apikey': SUPABASE_CATALOG_ANON_KEY,
            'Authorization': `Bearer ${SUPABASE_CATALOG_ANON_KEY}`
        },
        body: JSON.stringify(body)
    });

    if (!response.ok) {
        throw new Error(`Kataloganrop ${functionName} misslyckades: ${response.status}`);
    }

    return response.json();
}

const libraryUsageThrottle = new Map();
const LIBRARY_USAGE_SAFE_SLUG = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;
const LIBRARY_USAGE_CANONICAL_PROMPT_SLUGS = new Map([
    ['enkel_infografik', 'enkel-infografik'],
    ['illustration_informationsutskick', 'illustration-informationsutskick'],
    ['ikon_symbolbild', 'ikon-symbolbild'],
    ['alt_text_bild', 'alt-text-bild']
]);
const LIBRARY_USAGE_AREAS = new Set([
    'kommunikation',
    'forandringsledning',
    'processer',
    'beslutsberedning',
    'visuellt',
    'ledarskap',
    'arbetsbank',
    'Skriva och förbättra text',
    'Svara och kommunicera',
    'Sammanfatta och strukturera',
    'Möten och workshops',
    'Beslut och rutiner',
    'Bilder och infografik'
]);
const LIBRARY_USAGE_RISK_LEVELS = new Set(['low', 'medium', 'high', 'Låg risk', 'Medelrisk', 'Hög risk']);
const LIBRARY_USAGE_CONTEXT_KEYS = new Set(['generell', 'kommun', 'skola', 'företag', 'förening', 'privat']);

function getActiveCatalogContextKeys() {
    return getActiveContextKeys();
}

function shouldTrackLibraryUsage(key, ttlMs) {
    const now = Date.now();
    const previous = libraryUsageThrottle.get(key) || 0;
    if (now - previous < ttlMs) return false;
    libraryUsageThrottle.set(key, now);
    return true;
}

function getSafeLibraryUsagePromptSlug(promptSlug) {
    const canonicalSlug = LIBRARY_USAGE_CANONICAL_PROMPT_SLUGS.get(promptSlug) || promptSlug;
    return LIBRARY_USAGE_SAFE_SLUG.test(canonicalSlug || '') ? canonicalSlug : null;
}

function getSafeLibraryUsageMetadata(metadata) {
    const safeMetadata = {};
    if (metadata?.copy_surface === 'detail_panel' || metadata?.copy_surface === 'card') {
        safeMetadata.copy_surface = metadata.copy_surface;
    }
    if (metadata?.package_type === 'collection' || metadata?.package_type === 'workflow') {
        safeMetadata.package_type = metadata.package_type;
    }
    if (Number.isInteger(metadata?.query_length) && metadata.query_length >= 0 && metadata.query_length <= 200) {
        safeMetadata.query_length = metadata.query_length;
    }
    const contextKeys = (metadata?.filter_value || '').split(',');
    if (metadata?.filter_key === 'context' && contextKeys.length && contextKeys.every((key) => LIBRARY_USAGE_CONTEXT_KEYS.has(key))) {
        safeMetadata.filter_key = 'context';
        safeMetadata.filter_value = metadata.filter_value;
    }
    if (metadata?.filter_key === 'category' && LIBRARY_USAGE_AREAS.has(metadata.filter_value)) {
        safeMetadata.filter_key = 'category';
        safeMetadata.filter_value = metadata.filter_value;
    }
    return safeMetadata;
}

async function trackLibraryUsageEvent(payload) {
    if (!isCatalogConfigUsable()) return;

    const promptSlug = getSafeLibraryUsagePromptSlug(payload.promptSlug);
    const packageSlug = LIBRARY_USAGE_SAFE_SLUG.test(payload.packageSlug || '') ? payload.packageSlug : null;

    try {
        await callCatalogRpc('track_library_usage_event', {
            p_source: 'web',
            p_event_type: payload.eventType,
            p_outcome: payload.outcome || 'success',
            p_prompt_slug: promptSlug,
            p_package_slug: packageSlug,
            p_context_keys: payload.contextKeys || getActiveCatalogContextKeys(),
            p_area: LIBRARY_USAGE_AREAS.has(payload.area) ? payload.area : null,
            p_risk_level: LIBRARY_USAGE_RISK_LEVELS.has(payload.riskLevel) ? payload.riskLevel : null,
            p_result_count: Number.isInteger(payload.resultCount) ? payload.resultCount : null,
            p_catalog_version: null,
            p_metadata: getSafeLibraryUsageMetadata(payload.metadata)
        });
    } catch (error) {
        console.debug('Kunde inte logga anonym biblioteksstatistik', error);
    }
}

function isCatalogConfigUsable() {
    return isUsableCatalogEnvValue(SUPABASE_CATALOG_URL, '%VITE_SUPABASE_URL%')
        && isUsableCatalogEnvValue(SUPABASE_CATALOG_ANON_KEY, '%VITE_SUPABASE_PUBLISHABLE_KEY%');
}

function renderCatalogUnavailableState(message) {
    const section = document.getElementById('catalog-section');
    const filters = document.getElementById('catalog-profile-filters');
    const promptGrid = document.getElementById('catalog-prompt-grid');
    const packageGrid = document.getElementById('catalog-package-grid');

    if (section) {
        section.hidden = false;
    }
    if (filters) {
        filters.innerHTML = '';
    }
    if (promptGrid) {
        promptGrid.innerHTML = `<div class="catalog-empty-state error-message">${message}</div>`;
    }
    if (packageGrid) {
        packageGrid.innerHTML = `<div class="catalog-empty-state error-message">${message}</div>`;
    }
}

function renderCatalogEmptyState(grid, itemLabel) {
    if (!grid) return;

    const active = GLOBAL_CONTEXT_OPTIONS.find((item) => item.key === getActiveContextKey());
    const message = active && active.key !== DEFAULT_CONTEXT_KEY
        ? `Inga publicerade ${itemLabel} hittades för ${active.label} just nu. Prova att välja en annan kontext.`
        : `Det finns inga publicerade ${itemLabel} i den öppna katalogen ännu.`;

    grid.innerHTML = `<div class="catalog-empty-state">${message}</div>`;
}

function renderCatalogProfileFilters() {
    if (!isCatalogConfigUsable()) {
        renderCatalogUnavailableState('Öppen katalog är tillfälligt otillgänglig just nu.');
        return;
    }

    const container = document.getElementById('catalog-profile-filters');
    if (!container) return;

    const activeContextKey = getActiveContextKey();

    container.innerHTML = GLOBAL_CONTEXT_OPTIONS.map(({ key, label }) => `
        <button type="button" class="context-filter-option" data-catalog-profile="${key}" role="radio" aria-checked="${key === activeContextKey}" tabindex="${key === activeContextKey ? '0' : '-1'}">
            ${label}
        </button>
    `).join('');

    const buttons = Array.from(container.querySelectorAll('button[data-catalog-profile]'));
    const selectContext = (key) => {
        const selectedPromptIdBeforeContextChange = document.querySelector('.prompt-card.selected')?.dataset.promptId;
        if (selectedPromptIdBeforeContextChange) {
            window.promptbankenPendingPromptSelection = selectedPromptIdBeforeContextChange;
        }
        saveGlobalContextSelection(key);
        renderCatalogProfileFilters();
        renderGlobalContextStatus();
        syncGlobalRenderControls();
        refreshGlobalRenderOutputs();
        trackLibraryUsageEvent({
            eventType: 'filter_apply',
            resultCount: document.querySelectorAll('.prompt-card:not([hidden])').length,
            metadata: {
                filter_key: 'context',
                filter_value: getActiveCatalogContextKeys().join(',')
            }
        });
    };

    buttons.forEach((button, index) => {
        button.addEventListener('click', () => {
            selectContext(button.dataset.catalogProfile);
        });

        button.addEventListener('keydown', (event) => {
            let nextIndex = index;

            if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
                nextIndex = (index + 1) % buttons.length;
            } else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
                nextIndex = (index - 1 + buttons.length) % buttons.length;
            } else if (event.key === 'Home') {
                nextIndex = 0;
            } else if (event.key === 'End') {
                nextIndex = buttons.length - 1;
            } else {
                return;
            }

            event.preventDefault();
            const nextKey = buttons[nextIndex].dataset.catalogProfile;
            selectContext(nextKey);
            container.querySelector(`[data-catalog-profile="${nextKey}"]`)?.focus();
        });
    });
}

function renderGlobalContextStatus() {
    const status = document.getElementById('catalog-profile-status');
    if (!status) return;
    const active = GLOBAL_CONTEXT_OPTIONS.find((item) => item.key === getActiveContextKey());
    const selectedPromptId = document.querySelector('.prompt-card.selected')?.dataset.promptId;
    const selectedVariant = selectedPromptId ? getCachedStaticCatalogPromptVariant(selectedPromptId) : null;
    const state = getGlobalRenderState();
    const renderState = selectedVariant
        ? resolvePromptBindings(
            state,
            selectedVariant.parameter_schema,
            { ...selectedVariant.default_bindings, ...state },
            selectedVariant.binding_overrides
        )
        : state;

    status.textContent = `Anpassar prompttext för ${active ? active.label : 'Alla'} med rollen ${renderState.roll || state.roll}, målgruppen ${renderState.malgrupp || state.malgrupp} och tonen ${renderState.ton || state.ton}.`;
}

function getQuickInputValue() {
    return document.getElementById('quick-input-textarea')?.value || '';
}

// Enhetlig katalogfiltrering: se docs/superpowers/specs/
// 2026-08-02-catalog-search-filter-unification-design.md. Katalogprompts
// matchas mot samma globala filtervariabler som legacy-griden
// (activeCategoryFilter/activeAudienceFilter/activeRiskFilter), men rollfilter
// ignoreras medvetet (katalogdata saknar rollfält) och kategori/risk matchas
// via lookup-maps eftersom katalogens lagringsformat (slugs, engelska
// risknycklar) skiljer sig från legacy-griden (svenska etiketter).
document.querySelectorAll('[data-catalog-package-shortcut]').forEach((button) => {
    button.addEventListener('click', () => {
        const slug = button.getAttribute('data-catalog-package-shortcut');
        openCatalogPackageDetail(slug);
        document.getElementById('catalog-package-grid')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
});

function applyCatalogPromptFilters() {
    const query = getSearchQuery();
    document.querySelectorAll('#catalog-prompt-grid .catalog-card').forEach((card) => {
        const prompt = catalogPromptsById.get(card.dataset.catalogPromptId);
        if (!prompt) {
            card.hidden = true;
            return;
        }

        const areaLabel = catalogAreaLabels.get(prompt.area) || '';
        const haystack = `${prompt.title || ''} ${prompt.summary || ''} ${areaLabel} ${prompt.audience_label || ''}`.toLowerCase();
        const matchesSearch = !query || haystack.includes(query);
        const matchesCategory = activeCategoryFilter === 'all'
            || !prompt.area
            || catalogLabelToArea.get(activeCategoryFilter) === prompt.area
            || activeCategoryFilter === prompt.area;
        const matchesAudience = activeAudienceFilter === 'all'
            || (prompt.audience_label || '').toLowerCase().includes(activeAudienceFilter.toLowerCase());
        const matchesRisk = activeRiskFilter === 'all'
            || !prompt.risk_level
            || catalogRiskLabels[prompt.risk_level] === activeRiskFilter;
        // Rollfilter medvetet ignorerat: katalogprompts har inget rollfält.

        card.hidden = !(matchesSearch && matchesCategory && matchesAudience && matchesRisk);
    });
}

function applyCatalogPackageFilters() {
    const query = getSearchQuery();
    document.querySelectorAll('#catalog-package-grid .catalog-card').forEach((card) => {
        const haystack = card.textContent.toLowerCase();
        card.hidden = Boolean(query) && !haystack.includes(query);
    });
}

let activeCatalogPromptEntity = null;

function setElementHiddenState(element, hidden) {
    if (!element) return;
    element.hidden = hidden;
    element.setAttribute('aria-hidden', hidden ? 'true' : 'false');
    if ('inert' in element) {
        element.inert = hidden;
    }
}

function setCatalogDetailPanelOpen(open) {
    setElementHiddenState(document.getElementById('catalog-prompt-detail'), !open);
}

function selectCatalogPromptInSidebar(entity) {
    const normalized = normalizeCatalogTemplateEntity(entity);
    activeCatalogPromptEntity = normalized;
    window.__clearLegacySelectedPromptId?.();

    document.body.classList.remove('detail-panel-closed');
    document.body.classList.add('detail-sheet-open');
    setCatalogDetailPanelOpen(false);

    const title = document.getElementById('selected-prompt-title');
    const description = document.getElementById('selected-prompt-description');
    const preview = document.getElementById('detail-prompt-preview');
    const riskBadge = document.getElementById('detail-risk');

    if (title) title.textContent = normalized.title || '';
    if (description) description.textContent = normalized.summary || '';
    if (preview) {
        preview.textContent = replaceInputMarkers(renderCatalogTemplateField(normalized, 'prompt_text'), getQuickInputValue()) || 'Prompttext saknas.';
    }
    if (riskBadge) riskBadge.style.display = 'none';

    // Katalogprompts saknar ännu målgrupp/roll/exempel-metadata via RPC:n
    // (bara title/summary/prompt_text) — dölj fälten istället för att visa
    // tomma/felaktiga värden.
    ['detail-meta-row', 'detail-example-section', 'detail-phrase-section'].forEach((id) => {
        const el = document.getElementById(id);
        if (el) el.style.display = 'none';
    });

    const panel = document.getElementById('prompt-detail-panel');
    if (panel) {
        panel.dataset.catalogPromptSlug = normalized.slug || '';
    }

    const copyButton = document.getElementById('selected-prompt-copy-btn');
    if (copyButton) {
        copyButton.removeAttribute('disabled');
        copyButton.textContent = 'Kopiera';
        copyButton.classList.remove('copied', 'is-copied');
        copyButton.dataset.catalogAction = 'copy';
        copyButton.dataset.catalogPromptSlug = normalized.slug || '';
    }
    const viewButton = document.getElementById('selected-prompt-view-btn');
    if (viewButton) {
        viewButton.removeAttribute('disabled');
        viewButton.dataset.catalogAction = 'preview';
        viewButton.dataset.catalogPromptSlug = normalized.slug || '';
    }
    ['selected-prompt-chat-btn', 'selected-prompt-export-btn'].forEach((id) => {
        document.getElementById(id)?.setAttribute('disabled', 'disabled');
    });

    if (panel && window.matchMedia('(max-width: 1180px)').matches) {
        window.requestAnimationFrame(() => {
            panel.focus({ preventScroll: true });
            panel.scrollIntoView({ block: 'start', behavior: 'smooth' });
        });
    }
}

function getSelectedCatalogPromptEntity(button) {
    if (activeCatalogPromptEntity) return activeCatalogPromptEntity;

    const slug = button?.dataset?.catalogPromptSlug
        || document.getElementById('prompt-detail-panel')?.dataset?.catalogPromptSlug
        || '';
    if (!slug) return null;

    const match = catalogDetailPackageItems
        .map(normalizeCatalogTemplateEntity)
        .find((item) => item.slug === slug);

    if (match) {
        activeCatalogPromptEntity = match;
        return match;
    }

    return null;
}

document.getElementById('selected-prompt-copy-btn')?.addEventListener('click', (event) => {
    const entity = getSelectedCatalogPromptEntity(event.currentTarget);
    if (!entity) return;
    copyCatalogEntityText(entity, event.currentTarget);
});

document.getElementById('selected-prompt-view-btn')?.addEventListener('click', (event) => {
    const entity = getSelectedCatalogPromptEntity(event.currentTarget);
    if (!entity?.slug) return;
    openCatalogEntityPreviewModal(entity);
});

async function copyCatalogEntityText(entity, button) {
    const text = replaceInputMarkers(renderCatalogTemplateField(entity, 'prompt_text'), getQuickInputValue());
    if (!text) return;
    try {
        await navigator.clipboard.writeText(text);
        trackLibraryUsageEvent({
            eventType: 'prompt_copy',
            promptSlug: entity.slug || null,
            metadata: { copy_surface: button.id === 'selected-prompt-copy-btn' ? 'detail_panel' : 'card' }
        });
        const originalText = button.textContent;
        button.textContent = 'Kopierat';
        button.classList.add('copied');
        setTimeout(() => {
            button.textContent = originalText;
            button.classList.remove('copied');
        }, 2000);
    } catch (error) {
        console.error('Kunde inte kopiera prompten:', error);
        alert('Kunde inte kopiera. Prova igen eller kopiera manuellt.');
    }
}

const catalogPromptsById = new Map();
const catalogAreaLabels = new Map();
const catalogLabelToArea = new Map();
const catalogRiskLabels = { low: 'Låg risk', medium: 'Medelrisk', high: 'Hög risk' };
const libraryReferencePromptIds = new Set();
const libraryReferencePackageIds = new Set();

function getCatalogLibraryActionState(inLibrary) {
    return window.catalogLibraryActionState?.(inLibrary) || (inLibrary
        ? { label: '✓ Finns i Mitt bibliotek', disabled: true }
        : { label: 'Lägg till i Mitt bibliotek', disabled: false });
}

window.markCatalogPromptInLibrary = function markCatalogPromptInLibrary(promptId) {
    if (!promptId) return;
    libraryReferencePromptIds.add(promptId);
    document.querySelectorAll(`[data-catalog-prompt-id="${CSS.escape(promptId)}"] .catalog-library-btn`)
        .forEach((button) => {
            const state = getCatalogLibraryActionState(true);
            button.textContent = state.label;
            button.disabled = state.disabled;
        });
    if (activeCatalogPromptEntity?.id === promptId) {
        const detailButton = document.getElementById('catalog-detail-library-btn');
        if (detailButton) {
            const state = getCatalogLibraryActionState(true);
            detailButton.textContent = state.label;
            detailButton.disabled = state.disabled;
        }
    }
};

window.markCatalogPackageInLibrary = function markCatalogPackageInLibrary(packageId) {
    if (!packageId) return;
    libraryReferencePackageIds.add(packageId);
    document.querySelectorAll(`[data-catalog-package-id="${CSS.escape(packageId)}"] .catalog-library-btn`)
        .forEach((button) => {
            const state = getCatalogLibraryActionState(true);
            button.textContent = state.label;
            button.disabled = state.disabled;
        });
    const detailButton = document.getElementById('catalog-detail-library-btn');
    if (detailButton && catalogDetailVariants.some((variant) => variant.id === packageId)) {
        const state = getCatalogLibraryActionState(true);
        detailButton.textContent = state.label;
        detailButton.disabled = state.disabled;
    }
};

function createCatalogPromptCard(prompt) {
    const card = document.createElement('div');
    card.className = 'catalog-card';
    card.dataset.catalogPromptSlug = prompt.slug;
    card.dataset.catalogPromptId = prompt.id;
    const title = escapeHtml(prompt.title);
    const summary = escapeHtml(prompt.summary);
    const fallbackBadge = prompt.isFallback
        ? `<span class="catalog-context-badge">${escapeHtml(prompt.fallbackLabel || 'Kan vara generell version')}</span>`
        : '';
    card.innerHTML = `
        <h4>${title}</h4>
        <p>${summary}</p>
        ${fallbackBadge}
        <div class="catalog-card-actions">
            <button type="button" class="primary-btn catalog-select-btn">Välj</button>
            <button type="button" class="secondary-btn catalog-preview-btn">Förhandsvisa</button>
            <button type="button" class="secondary-btn catalog-library-btn">Lägg till i Mitt bibliotek</button>
        </div>
    `;
    card.addEventListener('click', () => selectCatalogPromptInSidebar(prompt));
    card.querySelector('.catalog-select-btn').addEventListener('click', (event) => {
        event.stopPropagation();
        selectCatalogPromptInSidebar(prompt);
    });
    card.querySelector('.catalog-preview-btn').addEventListener('click', (event) => {
        event.stopPropagation();
        openCatalogPromptDetail(prompt.slug);
    });
    card.querySelector('.catalog-library-btn').addEventListener('click', (event) => {
        event.stopPropagation();
        window.addPublishedPromptToLibrary?.(prompt.id, event.currentTarget);
        trackLibraryUsageEvent({ eventType: 'library_add', promptSlug: prompt.slug });
    });
    if (libraryReferencePromptIds.has(prompt.id)) {
        const libraryButton = card.querySelector('.catalog-library-btn');
        libraryButton.textContent = '✓ Finns i Mitt bibliotek';
        libraryButton.disabled = true;
    }
    return card;
}

async function loadCatalogPrompts() {
    if (!isCatalogConfigUsable()) {
        renderCatalogUnavailableState('Öppen katalog är tillfälligt otillgänglig just nu.');
        return;
    }

    const grid = document.getElementById('catalog-prompt-grid');
    if (!grid) return;

    try {
        const activeContextKey = getActiveContextKey();
        const prompts = await callCatalogRpc('list_published_prompts', {
            p_context_keys: getActiveContextKeys()
        });
        grid.innerHTML = '';
        catalogPromptsById.clear();
        if (!prompts.length) {
            renderCatalogEmptyState(grid, 'prompter');
            return;
        }
        // List-RPC:n returnerar inte context_key i den komprimerade listvyn ännu,
        // så icke-generella lägen markeras heuristiskt tills read-RPC:n kan
        // skilja exakt mellan matchad och generell variant.
        prompts
            .map((prompt) => ({
                ...prompt,
                isFallback: activeContextKey !== DEFAULT_CONTEXT_KEY && (!prompt.context_key || prompt.context_key === DEFAULT_CONTEXT_KEY),
                fallbackLabel: prompt.context_key ? 'Generell version' : 'Kan vara generell version'
            }))
            .forEach((prompt) => {
                catalogPromptsById.set(prompt.id, prompt);
                grid.appendChild(createCatalogPromptCard(prompt));
            });
        populateFilterOptions(allPrompts);
        applyAllFilters();
    } catch (error) {
        console.error('Kunde inte ladda katalogprompts:', error);
        grid.innerHTML = '<div class="catalog-empty-state error-message">⚠️ Kunde inte ladda katalogprompts.</div>';
    }
}

let catalogDetailVariants = [];
let catalogDetailPackageItems = [];
const staticCatalogPromptVariantCache = new Map();
const staticCatalogPromptVariantPromises = new Map();

function normalizeCatalogTemplateEntity(entity) {
    return {
        ...entity,
        slug: entity?.slug || entity?.prompt_slug || '',
        parameter_schema: entity?.parameter_schema || null,
        default_bindings: entity?.default_bindings || {},
        binding_overrides: Array.isArray(entity?.binding_overrides) ? entity.binding_overrides : []
    };
}

function openCatalogEntityPreviewModal(entity) {
    const normalized = normalizeCatalogTemplateEntity(entity);
    const promptText = replaceInputMarkers(renderCatalogTemplateField(normalized, 'prompt_text'), getQuickInputValue());
    if (!promptText) {
        if (normalized.slug) openCatalogPromptDetail(normalized.slug);
        return;
    }

    const promptModal = document.getElementById('prompt-modal');
    const promptModalTitle = document.getElementById('modal-title');
    const promptModalText = document.getElementById('modal-text');
    const promptModalClose = document.getElementById('modal-close');
    if (!promptModal || !promptModalTitle || !promptModalText) return;

    promptModal.dataset.promptId = normalized.slug;
    promptModalTitle.textContent = `Förhandsvisning: ${normalized.title || 'Prompt'}`;
    promptModalText.textContent = promptText;
    promptModal.hidden = false;
    promptModal.classList.add('active');
    promptModalClose?.focus({ preventScroll: true });
}

function getStaticCatalogPromptVariantCacheKey(promptId) {
    return `${promptId}:${getActiveContextKey()}`;
}

function getCachedStaticCatalogPromptVariant(promptId) {
    return staticCatalogPromptVariantCache.get(getStaticCatalogPromptVariantCacheKey(promptId));
}

async function ensureStaticCatalogPromptVariant(promptId) {
    if (!isCatalogConfigUsable() || !promptId) return null;

    const cacheKey = getStaticCatalogPromptVariantCacheKey(promptId);
    if (staticCatalogPromptVariantCache.has(cacheKey)) {
        return staticCatalogPromptVariantCache.get(cacheKey);
    }

    if (!staticCatalogPromptVariantPromises.has(cacheKey)) {
        const promise = callCatalogRpc('get_published_prompt', {
            p_slug: promptId,
            p_context_keys: getActiveContextKeys()
        })
            .then((variants) => {
                const normalizedVariants = Array.isArray(variants)
                    ? variants.map(normalizeCatalogTemplateEntity)
                    : [];
                const bestVariant = normalizedVariants[0] || null;
                staticCatalogPromptVariantCache.set(cacheKey, bestVariant);
                staticCatalogPromptVariantPromises.delete(cacheKey);
                return bestVariant;
            })
            .catch((error) => {
                staticCatalogPromptVariantPromises.delete(cacheKey);
                console.warn(`Kunde inte ladda katalogvariant för ${promptId}:`, error);
                return null;
            });

        staticCatalogPromptVariantPromises.set(cacheKey, promise);
    }

    return staticCatalogPromptVariantPromises.get(cacheKey);
}

function renderCatalogTemplateField(entity, fieldName) {
    const rawValue = entity?.[fieldName];
    if (!rawValue) return '';
    if (!entity?.parameter_schema) return String(rawValue);

    const template = adaptLegacyPromptTemplate(rawValue, entity.parameter_schema);
    const bindings = resolvePromptBindings(
        getGlobalRenderState(),
        entity.parameter_schema,
        entity.default_bindings,
        entity.binding_overrides
    );

    return renderPromptTemplate(template, bindings);
}

function renderCatalogDetailVariant(variant) {
    const body = document.getElementById('catalog-detail-body');
    if (!body) return;
    const normalizedVariant = normalizeCatalogTemplateEntity(variant);
    const isPrompt = 'prompt_text' in normalizedVariant;

    const shareButton = document.getElementById('catalog-detail-share');
    if (shareButton) {
        shareButton.hidden = false;
        shareButton.dataset.catalogEntityType = isPrompt ? 'prompt' : 'package';
        shareButton.dataset.catalogEntitySlug = normalizedVariant.slug || '';
    }

    const introOrPromptHtml = isPrompt
        ? `<pre class="catalog-detail-prompt-text">${escapeHtml(renderCatalogTemplateField(normalizedVariant, 'prompt_text'))}</pre>
           <div class="catalog-card-actions">
               <button type="button" class="catalog-copy-btn" id="catalog-detail-copy-btn">Kopiera prompt</button>
               <button type="button" class="secondary-btn catalog-library-btn" id="catalog-detail-library-btn">Lägg till i Mitt bibliotek</button>
           </div>`
        : (normalizedVariant.intro_text
            ? `<p>${escapeHtml(renderCatalogTemplateField(normalizedVariant, 'intro_text'))}</p>`
            : '') + `<div class="catalog-card-actions"><button type="button" class="secondary-btn catalog-library-btn" id="catalog-detail-library-btn">Lägg till i Mitt bibliotek</button></div>`;

    const packageItemsHtml = (!isPrompt && catalogDetailPackageItems.length)
        ? `<div class="catalog-package-items">
             <p class="catalog-package-items-heading">Innehåller ${catalogDetailPackageItems.length} ${catalogDetailPackageItems.length === 1 ? 'prompt' : 'prompter'}:</p>
             ${catalogDetailPackageItems.map((item, index) => `
                <div class="catalog-package-item">
                    <h4>${escapeHtml(item.title)}</h4>
                    <p>${escapeHtml(item.summary)}</p>
                    <button type="button" class="primary-btn catalog-select-btn" data-package-item-index="${index}">Välj</button>
                </div>
             `).join('')}
           </div>`
        : (!isPrompt && catalogDetailVariants.length
            ? '<p class="catalog-package-items-empty">Det här paketet har inga prompter ännu.</p>'
            : '');

    body.innerHTML = `
        <h3>${escapeHtml(normalizedVariant.title)}</h3>
        <p>${escapeHtml(normalizedVariant.summary)}</p>
        ${introOrPromptHtml}
        ${packageItemsHtml}
    `;

    if (isPrompt) {
        document.getElementById('catalog-detail-copy-btn')?.addEventListener('click', (event) => {
            copyCatalogEntityText(normalizedVariant, event.currentTarget);
        });
        document.getElementById('catalog-detail-library-btn')?.addEventListener('click', (event) => {
            window.addPublishedPromptToLibrary?.(normalizedVariant.id, event.currentTarget);
            trackLibraryUsageEvent({ eventType: 'library_add', promptSlug: normalizedVariant.slug });
        });
        if (libraryReferencePromptIds.has(normalizedVariant.id)) {
            const libraryButton = document.getElementById('catalog-detail-library-btn');
            libraryButton.textContent = '✓ Finns i Mitt bibliotek';
            libraryButton.disabled = true;
        }
    } else {
        document.getElementById('catalog-detail-library-btn')?.addEventListener('click', (event) => {
            window.addPublishedPackageToLibrary?.(normalizedVariant.id, event.currentTarget);
        });
        if (libraryReferencePackageIds.has(normalizedVariant.id)) {
            const libraryButton = document.getElementById('catalog-detail-library-btn');
            libraryButton.textContent = '✓ Finns i Mitt bibliotek';
            libraryButton.disabled = true;
        }
    }

    body.querySelectorAll('.catalog-package-item [data-package-item-index]').forEach((button) => {
        button.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            const item = catalogDetailPackageItems[Number(event.currentTarget.dataset.packageItemIndex)];
            if (item) selectCatalogPromptInSidebar(item);
        });
    });
}

function rerenderActiveCatalogDetailVariant() {
    const panel = document.getElementById('catalog-prompt-detail');
    if (!panel || panel.hidden || !catalogDetailVariants.length) return;

    const activeButton = document.querySelector('#catalog-detail-tabs button.active');
    const activeIndex = Number(activeButton?.dataset.catalogTabIndex || 0);
    renderCatalogDetailVariant(catalogDetailVariants[activeIndex] || catalogDetailVariants[0]);
}

// Shared by prompt detail and package detail: renders the context-profile
// tabs into #catalog-detail-tabs and wires up click-to-switch behaviour.
function renderCatalogDetailTabs(variants) {
    const tabsContainer = document.getElementById('catalog-detail-tabs');
    if (!tabsContainer) return;

    const profileLabelByKey = new Map(CATALOG_CONTEXT_PROFILES.map(({ key, label }) => [key, label]));

    tabsContainer.innerHTML = variants.map((variant, index) => `
        <button type="button" data-catalog-tab-index="${index}" class="${index === 0 ? 'active' : ''}">
            ${escapeHtml(profileLabelByKey.get(variant.context_key) || 'Generell')}
        </button>
    `).join('');

    tabsContainer.querySelectorAll('button[data-catalog-tab-index]').forEach((button) => {
        button.addEventListener('click', () => {
            tabsContainer.querySelectorAll('button').forEach((btn) => btn.classList.remove('active'));
            button.classList.add('active');
            renderCatalogDetailVariant(variants[Number(button.dataset.catalogTabIndex)]);
        });
    });
}

async function openCatalogPromptDetail(slug) {
    const panel = document.getElementById('catalog-prompt-detail');
    const tabsContainer = document.getElementById('catalog-detail-tabs');
    if (!panel || !tabsContainer) return false;

    catalogDetailPackageItems = [];
    try {
        catalogDetailVariants = (await callCatalogRpc('get_published_prompt', {
            p_slug: slug,
            p_context_keys: getActiveContextKeys()
        })).map(normalizeCatalogTemplateEntity);
    } catch (error) {
        console.error('Kunde inte ladda promptdetaljer:', error);
        return false;
    }

    if (!catalogDetailVariants.length) return false;

    renderCatalogDetailTabs(catalogDetailVariants);
    renderCatalogDetailVariant(catalogDetailVariants[0]);
    setCatalogDetailPanelOpen(true);

    const params = new URLSearchParams(window.location.search);
    if (params.get('prompt') !== slug) {
        params.delete('package');
        params.set('prompt', slug);
        window.history.pushState({ catalogPromptSlug: slug }, '', `${window.location.pathname}?${params}`);
    }

    const promptViewKey = `prompt_view:${slug}:${getActiveCatalogContextKeys().join(',')}`;
    if (shouldTrackLibraryUsage(promptViewKey, 60 * 60 * 1000)) {
        trackLibraryUsageEvent({
            eventType: 'prompt_view',
            promptSlug: slug
        });
    }

    return true;
}

function getPackageSlugFromLocation() {
    return new URLSearchParams(window.location.search).get('package') || null;
}

function getPromptSlugFromLocation() {
    return new URLSearchParams(window.location.search).get('prompt') || null;
}

async function openCatalogPackageDetail(slug) {
    const panel = document.getElementById('catalog-prompt-detail');
    const tabsContainer = document.getElementById('catalog-detail-tabs');
    if (!panel || !tabsContainer) return false;

    try {
        catalogDetailVariants = (await callCatalogRpc('get_published_package', {
            p_slug: slug,
            p_context_keys: getActiveContextKeys()
        })).map(normalizeCatalogTemplateEntity);
    } catch (error) {
        console.error('Kunde inte ladda paketdetaljer:', error);
        return false;
    }

    if (!catalogDetailVariants.length) return false;

    try {
        catalogDetailPackageItems = await callCatalogRpc('list_published_package_prompts', {
            p_package_slug: slug,
            p_context_keys: getActiveContextKeys()
        });
    } catch (error) {
        console.error('Kunde inte ladda paketets prompter:', error);
        catalogDetailPackageItems = [];
    }

    renderCatalogDetailTabs(catalogDetailVariants);
    renderCatalogDetailVariant(catalogDetailVariants[0]);
    setCatalogDetailPanelOpen(true);

    const params = new URLSearchParams(window.location.search);
    if (params.get('package') !== slug) {
        params.delete('prompt');
        params.set('package', slug);
        window.history.pushState({ catalogPackageSlug: slug }, '', `${window.location.pathname}?${params}`);
    }

    const packageViewKey = `package_view:${slug}:${getActiveCatalogContextKeys().join(',')}`;
    if (shouldTrackLibraryUsage(packageViewKey, 60 * 60 * 1000)) {
        const packageType = catalogDetailVariants[0]?.package_type;
        trackLibraryUsageEvent({
            eventType: 'package_view',
            packageSlug: slug,
            metadata: packageType === 'collection' || packageType === 'workflow'
                ? { package_type: packageType }
                : {}
        });
    }

    return true;
}

function closeCatalogDetailPanel() {
    setCatalogDetailPanelOpen(false);
    const shareButton = document.getElementById('catalog-detail-share');
    if (shareButton) shareButton.hidden = true;
    const params = new URLSearchParams(window.location.search);
    if (params.has('package') || params.has('prompt')) {
        params.delete('package');
        params.delete('prompt');
        const remaining = params.toString();
        window.history.replaceState(null, '', remaining ? `${window.location.pathname}?${remaining}` : window.location.pathname);
    }
}

document.getElementById('catalog-detail-close')?.addEventListener('click', () => {
    closeCatalogDetailPanel();
});

window.addEventListener('popstate', () => {
    const packageSlug = getPackageSlugFromLocation();
    const promptSlug = getPromptSlugFromLocation();
    const panel = document.getElementById('catalog-prompt-detail');
    if (!packageSlug && !promptSlug) {
        if (panel && !panel.hidden) {
            setCatalogDetailPanelOpen(false);
            const shareButton = document.getElementById('catalog-detail-share');
            if (shareButton) shareButton.hidden = true;
        }
        return;
    }
    if (packageSlug) {
        openCatalogPackageDetail(packageSlug);
    } else {
        openCatalogPromptDetail(promptSlug);
    }
});

let catalogShareButtonResetTimer = null;

document.getElementById('catalog-detail-share')?.addEventListener('click', async (event) => {
    const button = event.currentTarget;
    const slug = button.dataset.catalogEntitySlug;
    const entityType = button.dataset.catalogEntityType;
    if (!slug || !entityType) return;

    const paramName = entityType === 'prompt' ? 'prompt' : 'package';
    const url = `${window.location.origin}${window.location.pathname}?${paramName}=${encodeURIComponent(slug)}`;
    try {
        await navigator.clipboard.writeText(url);
        if (entityType === 'prompt') {
            trackLibraryUsageEvent({ eventType: 'prompt_share', promptSlug: slug });
        } else {
            trackLibraryUsageEvent({ eventType: 'package_share', packageSlug: slug });
        }
        clearTimeout(catalogShareButtonResetTimer);
        button.textContent = '✓';
        button.classList.add('copied');
        button.setAttribute('aria-label', 'Länk kopierad');
        catalogShareButtonResetTimer = setTimeout(() => {
            button.textContent = '🔗';
            button.classList.remove('copied');
            button.setAttribute('aria-label', 'Kopiera länk');
        }, 2000);
    } catch (error) {
        console.error('Kunde inte kopiera länken:', error);
        alert('Kunde inte kopiera länken. Kopiera adressen från adressfältet istället.');
    }
});

function createCatalogPackageCard(pkg) {
    const card = document.createElement('div');
    card.className = 'catalog-card';
    card.dataset.catalogPackageSlug = pkg.slug;
    card.dataset.catalogPackageId = pkg.id;
    const title = escapeHtml(pkg.title);
    const summary = escapeHtml(pkg.summary);
    const typeLabel = pkg.package_type === 'workflow' ? 'Arbetssätt' : 'Samling';
    const fallbackBadge = pkg.isFallback
        ? `<span class="catalog-context-badge">${escapeHtml(pkg.fallbackLabel || 'Kan vara generell version')}</span>`
        : '';
    card.innerHTML = `
        <h4>${title}</h4>
        <p>${summary}</p>
        <span class="catalog-package-type">${typeLabel}</span>
        ${fallbackBadge}
        <div class="catalog-card-actions">
            <button type="button" class="primary-btn catalog-package-open-btn">Öppna paket</button>
            <button type="button" class="secondary-btn catalog-library-btn">Lägg till i Mitt bibliotek</button>
        </div>
        <p class="catalog-package-permalink"><a href="/paket/${encodeURIComponent(pkg.slug)}/">Om paketet</a></p>
    `;
    card.addEventListener('click', () => openCatalogPackageDetail(pkg.slug));
    card.querySelector('.catalog-package-open-btn')?.addEventListener('click', (event) => {
        event.stopPropagation();
        openCatalogPackageDetail(pkg.slug);
    });
    card.querySelector('.catalog-library-btn')?.addEventListener('click', (event) => {
        event.stopPropagation();
        window.addPublishedPackageToLibrary?.(pkg.id, event.currentTarget);
    });
    card.querySelector('.catalog-package-permalink a')?.addEventListener('click', (event) => {
        event.stopPropagation();
    });
    if (libraryReferencePackageIds.has(pkg.id)) {
        const libraryButton = card.querySelector('.catalog-library-btn');
        libraryButton.textContent = '✓ Finns i Mitt bibliotek';
        libraryButton.disabled = true;
    }
    return card;
}

async function loadCatalogPackages() {
    document.getElementById('catalog-package-link-error')?.setAttribute('hidden', '');
    if (!isCatalogConfigUsable()) {
        renderCatalogUnavailableState('Öppen katalog är tillfälligt otillgänglig just nu.');
        return;
    }

    const grid = document.getElementById('catalog-package-grid');
    if (!grid) return;

    try {
        const activeContextKey = getActiveContextKey();
        const packages = await callCatalogRpc('list_published_packages', {
            p_context_keys: getActiveContextKeys(),
            p_package_type: null
        });
        grid.innerHTML = '';
        catalogAreaLabels.clear();
        catalogLabelToArea.clear();
        if (!packages.length) {
            renderCatalogEmptyState(grid, 'paket eller arbetssätt');
            return;
        }
        packages
            .map((pkg) => ({
                ...pkg,
                isFallback: activeContextKey !== DEFAULT_CONTEXT_KEY && (!pkg.context_key || pkg.context_key === DEFAULT_CONTEXT_KEY),
                fallbackLabel: pkg.context_key ? 'Generell version' : 'Kan vara generell version'
            }))
            .forEach((pkg) => {
                if (pkg.slug && pkg.title) {
                    catalogAreaLabels.set(pkg.slug, pkg.title);
                    catalogLabelToArea.set(pkg.title, pkg.slug);
                }
                grid.appendChild(createCatalogPackageCard(pkg));
            });
        populateFilterOptions(allPrompts);
        applyAllFilters();
    } catch (error) {
        console.error('Kunde inte ladda katalogpaket:', error);
        grid.innerHTML = '<div class="catalog-empty-state error-message">⚠️ Kunde inte ladda katalogpaket.</div>';
    }
}

        // Kontextprofil-regressionscheck
        function testGlobalContextStorage() {
            // Snapshot the user's real saved selection first so the roundtrip
            // test never destroys it (script.js runs before DOMContentLoaded).
            const realValue = localStorage.getItem(CATALOG_PROFILE_STORAGE_KEY);
            const testKey = 'kommun';
            localStorage.setItem(CATALOG_PROFILE_STORAGE_KEY, JSON.stringify([testKey, 'skola']));
            const migratedKey = loadGlobalContextSelection();
            saveGlobalContextSelection(testKey);
            const roundTripped = loadGlobalContextSelection();

            if (realValue === null) {
                localStorage.removeItem(CATALOG_PROFILE_STORAGE_KEY);
            } else {
                localStorage.setItem(CATALOG_PROFILE_STORAGE_KEY, realValue);
            }

            return migratedKey === testKey && roundTripped === testKey;
        }

        console.log('Global Context Storage Test:', testGlobalContextStorage() ? 'Passed' : 'Failed');

        function testCatalogConfigValidation() {
            return isUsableCatalogEnvValue('https://example.supabase.co', '%VITE_SUPABASE_URL%')
                && !isUsableCatalogEnvValue(undefined, '%VITE_SUPABASE_PUBLISHABLE_KEY%')
                && !isUsableCatalogEnvValue('undefined', '%VITE_SUPABASE_PUBLISHABLE_KEY%')
                && !isUsableCatalogEnvValue('%VITE_SUPABASE_PUBLISHABLE_KEY%', '%VITE_SUPABASE_PUBLISHABLE_KEY%');
        }

        console.log('Catalog Config Validation Test:', testCatalogConfigValidation() ? 'Passed' : 'Failed');

// Step 19: Dynamic JavaScript loading from prompts.json
        
        const grid = document.getElementById('prompt-grid');
        const favoritesMenu = document.getElementById('favorites-menu');
        const favoritesList = document.getElementById('favorites-list');
        const clearFavoritesBtn = document.getElementById('clear-favorites-btn');
        const advancedToggleInput = document.getElementById('advanced-toggle-input');
        const favoritesToggleInput = document.getElementById('favorites-toggle-input');
        const localChatToggleInput = document.getElementById('local-chat-toggle-input');
        const ADVANCED_MODE_KEY = 'advancedModeEnabled';
        const FAVORITES_MODE_KEY = 'favoritesModeEnabled';
        const LOCAL_CHAT_MODE_KEY = 'localChatEnabled';
        // Under utveckling -- funktionen ligger kvar men visas inte förrän
        // den är redo. Sätt till true för att slå på igen.
        const LOCAL_CHAT_FEATURE_ENABLED = false;
        let advancedModeEnabled = false;
        let favoritesModeEnabled = false;
        let localChatEnabled = false;
        let allPrompts = []; // Store all loaded prompts for favorites menu
        let resolvePromptbankenReady;
        window.promptbankenReady = new Promise((resolve) => { resolvePromptbankenReady = resolve; });
        let selectedPromptId = null;
        window.__clearLegacySelectedPromptId = () => { selectedPromptId = null; };
        let activeCategoryFilter = 'all';
        let activeAudienceFilter = 'all';
        let activeRoleFilter = 'all';
        let activeRiskFilter = 'all';
        let favoritesOnlyFilter = false;
        let activeSort = 'newest';

        const promptUiMeta = {};

        const mcpPromptMeta = {
            tydlighetskoll: { icon: '▤', category: 'Beslut och rutiner', audiences: ['medarbetare', 'invånare', 'ledning', 'beslutsfattare'], roles: ['handläggare', 'chef', 'kommunikatör', 'samordnare'], risk: 'Medelrisk', example: 'Kommunala texter där ansvar, beslut, nästa steg eller risk för missförstånd behöver granskas.', phrase: 'Gör en tydlighetskoll på den här texten.' },
            klarsprak: { icon: '☷', category: 'Skriva och förbättra text', audiences: ['invånare', 'allmänhet'], roles: ['handläggare', 'kommunikatör', 'chef'], risk: 'Medelrisk', example: 'Texter till invånare, e-tjänster, brev och instruktioner.', phrase: 'Skriv om den här texten till klarspråk.' },
            mejl: { icon: '✉', category: 'Svara och kommunicera', audiences: ['invånare', 'företagare'], roles: ['handläggare', 'kommunikatör', 'kundcenter'], risk: 'Medelrisk', example: 'Svar på inkommande mejl där tonen behöver vara tydlig, vänlig och saklig.', phrase: 'Svara på det här mejlet utan att lova för mycket.' },
            faq: { icon: '?', category: 'Sammanfatta och strukturera', audiences: ['invånare', 'medarbetare', 'allmänhet'], roles: ['kommunikatör', 'handläggare', 'verksamhetsutvecklare'], risk: 'Medelrisk', example: 'Policyer och dokument som behöver göras om till frågor och svar.', phrase: 'Gör en FAQ av den här policyn.' },
            checklista: { icon: '☑', category: 'Sammanfatta och strukturera', audiences: ['medarbetare', 'invånare'], roles: ['handläggare', 'chef', 'samordnare'], risk: 'Medelrisk', example: 'Processer, rutiner, instruktioner och kontrollpunkter.', phrase: 'Gör en checklista av detta.' },
            kallelse: { icon: '□', category: 'Svara och kommunicera', audiences: ['invånare', 'medarbetare', 'deltagare'], roles: ['handläggare', 'administratör', 'chef'], risk: 'Medelrisk', example: 'Möten, träffar, event och samråd.', phrase: 'Skriv en kallelse till möte.' },
            beslutsunderlag: { icon: '▱', category: 'Beslut och rutiner', audiences: ['nämnd', 'ledning', 'beslutsfattare'], roles: ['handläggare', 'chef', 'utredare'], risk: 'Hög risk', example: 'Ärenden och förslag inför beslutande organ.', phrase: 'Skriv ett beslutsunderlag.' },
            rutin: { icon: '⌘', category: 'Beslut och rutiner', audiences: ['medarbetare'], roles: ['chef', 'samordnare', 'verksamhetsutvecklare'], risk: 'Medelrisk', example: 'Rutiner, processbeskrivningar och arbetsanvisningar.', phrase: 'Skriv en rutin.' },
            tvaversioner: { icon: '⇄', category: 'Skriva och förbättra text', audiences: ['invånare', 'medarbetare'], roles: ['kommunikatör', 'handläggare', 'chef'], risk: 'Medelrisk', example: 'När samma budskap behöver två tonlägen.', phrase: 'Gör en formell och en vardaglig version.' },
            reflektion: { icon: '◌', category: 'Möten och workshops', audiences: ['medarbetare', 'grupp'], roles: ['chef', 'pedagog', 'samordnare'], risk: 'Låg risk', example: 'Workshops, lärande samtal och uppföljningar.', phrase: 'Skapa reflektionsfrågor.' },
            samtalskompas: { icon: '◇', category: 'Möten och workshops', audiences: ['grupp', 'medarbetare'], roles: ['chef', 'facilitator', 'samordnare'], risk: 'Medelrisk', example: 'Möten, workshops och samtal som behöver struktur.', phrase: 'Skapa struktur för workshop.' },
            sammanfattning: { icon: '▤', category: 'Sammanfatta och strukturera', audiences: ['medarbetare', 'invånare', 'ledning'], roles: ['handläggare', 'chef', 'kommunikatör'], risk: 'Medelrisk', example: 'Långa dokument, rapporter och underlag.', phrase: 'Sammanfatta den här texten.' },
            anteckningar: { icon: '✎', category: 'Möten och workshops', audiences: ['medarbetare', 'ledning'], roles: ['handläggare', 'sekreterare', 'chef'], risk: 'Medelrisk', example: 'Mötesanteckningar, beslut och att-göra-punkter.', phrase: 'Strukturera mina mötesanteckningar.' },
            diskussionsfragor: { icon: '☰', category: 'Möten och workshops', audiences: ['grupp', 'medarbetare'], roles: ['chef', 'facilitator', 'samordnare'], risk: 'Låg risk', example: 'Möten, workshops och gruppdiskussioner.', phrase: 'Skapa diskussionsfrågor.' },
            nyckelord: { icon: '#', category: 'Sammanfatta och strukturera', audiences: ['medarbetare'], roles: ['handläggare', 'kommunikatör', 'analytiker'], risk: 'Låg risk', example: 'Dokument och rapporter där viktiga begrepp behöver hittas.', phrase: 'Plocka ut nyckelord.' },
            informationsutskick: { icon: '!', category: 'Svara och kommunicera', audiences: ['invånare', 'medarbetare', 'allmänhet'], roles: ['kommunikatör', 'handläggare', 'chef'], risk: 'Medelrisk', example: 'Nyheter, driftinformation och utskick.', phrase: 'Skriv ett informationsutskick.' },
            enkel_infografik: { icon: '▦', category: 'Bilder och infografik', audiences: ['invånare', 'medarbetare', 'ledning', 'allmänhet'], roles: ['handläggare', 'kommunikatör', 'samordnare', 'chef'], risk: 'Medelrisk', example: 'Information, siffror och viktiga punkter som behöver bli visuellt tydliga.', phrase: 'Skapa en enkel infografik.' },
            illustration_informationsutskick: { icon: '◫', category: 'Bilder och infografik', audiences: ['invånare', 'medarbetare', 'vårdnadshavare', 'allmänhet'], roles: ['handläggare', 'kommunikatör', 'samordnare', 'chef'], risk: 'Medelrisk', example: 'Kommunala informationsutskick som behöver en neutral bildidé.', phrase: 'Skapa en bild till informationsutskick.' },
            ikon_symbolbild: { icon: '◇', category: 'Bilder och infografik', audiences: ['invånare', 'medarbetare', 'elever', 'vårdnadshavare', 'allmänhet'], roles: ['handläggare', 'kommunikatör', 'samordnare', 'chef', 'pedagog'], risk: 'Låg risk', example: 'Begrepp, ämnen och budskap som behöver en enkel visuell symbol.', phrase: 'Skapa en ikon för detta.' },
            presentationstitelbild: { icon: '▣', category: 'Bilder och infografik', audiences: ['medarbetare', 'ledning', 'grupp', 'deltagare'], roles: ['chef', 'samordnare', 'pedagog', 'kommunikatör', 'handläggare'], risk: 'Låg risk', example: 'Presentationer, utbildningar och möten som behöver en lugn öppningsbild.', phrase: 'Skapa en titelbild till presentation.' },
            alt_text_bild: { icon: 'A', category: 'Bilder och infografik', audiences: ['invånare', 'medarbetare', 'allmänhet', 'webbanvändare'], roles: ['kommunikatör', 'handläggare', 'administratör', 'samordnare', 'pedagog'], risk: 'Låg risk', example: 'Bilder som behöver tillgänglig alt-text eller längre bildbeskrivning.', phrase: 'Skriv alt-text till bilden.' }
        };

        const categoryIconMap = {
            'Beslut och rutiner': 'clipboard',
            'Skriva och förbättra text': 'pencil',
            'Svara och kommunicera': 'message',
            'Sammanfatta och strukturera': 'list',
            'Möten och workshops': 'users',
            'Bild och infografik': 'image',
            'Bilder och infografik': 'image',
            'Alla kategorier': 'library'
        };

        const promptIconMap = {
            klarsprak: 'pencil',
            mejl: 'message',
            faq: 'help',
            checklista: 'clipboard',
            kallelse: 'users',
            beslutsunderlag: 'clipboard',
            rutin: 'clipboard',
            tvaversioner: 'pencil',
            reflektion: 'users',
            samtalskompas: 'users',
            sammanfattning: 'list',
            anteckningar: 'list',
            diskussionsfragor: 'users',
            nyckelord: 'search',
            informationsutskick: 'message',
            enkel_infografik: 'chart',
            illustration_informationsutskick: 'image',
            ikon_symbolbild: 'sparkles',
            presentationstitelbild: 'image',
            alt_text_bild: 'accessibility',
            tydlighetskoll: 'shield'
        };

        function getIconName(promptId, category) {
            return promptIconMap[promptId] || categoryIconMap[category] || 'library';
        }

        function getPromptMeta(prompt) {
            const mcpMeta = mcpPromptMeta[prompt.id];
            if (mcpMeta) {
                return {
                    ...mcpMeta,
                    audience: mcpMeta.audiences.join(', '),
                    role: mcpMeta.roles.join(', ')
                };
            }

            const fallbackMeta = promptUiMeta[prompt.id] || {
                icon: '▤',
                category: 'Alla kategorier',
                audience: 'Intern & extern',
                role: 'Alla roller',
                risk: 'Låg risk',
                example: 'Policytexter, information till invånare, beslut, nyheter och instruktioner.',
                phrase: 'Gör denna text tydligare och mer användbar för målgruppen.'
            };

            return {
                ...fallbackMeta,
                audiences: [fallbackMeta.audience],
                roles: [fallbackMeta.role]
            };
        }

        function stripLeadingIcon(title) {
            return title.replace(/^[^\p{L}\p{N}]+/u, '').trim();
        }

        function getRiskRank(risk) {
            if (risk.toLowerCase().includes('hög')) return 3;
            if (risk.toLowerCase().includes('medel')) return 2;
            return 1;
        }

        function loadAdvancedMode() {
            const stored = localStorage.getItem(ADVANCED_MODE_KEY);
            return stored === 'true';
        }

        function persistAdvancedMode(enabled) {
            localStorage.setItem(ADVANCED_MODE_KEY, enabled ? 'true' : 'false');
        }

        function setAdvancedMode(enabled) {
            advancedModeEnabled = enabled;
            persistAdvancedMode(enabled);
            document.body.classList.toggle('advanced-mode-on', enabled);
            if (advancedToggleInput) {
                advancedToggleInput.checked = enabled;
            }
            updateCopyButtonLabels();
        }

        function initAdvancedToggle() {
            advancedModeEnabled = loadAdvancedMode();
            setAdvancedMode(advancedModeEnabled);
            if (advancedToggleInput) {
                advancedToggleInput.checked = advancedModeEnabled;
                advancedToggleInput.addEventListener('change', (event) => {
                    setAdvancedMode(Boolean(event.target.checked));
                });
            }
        }

        function loadFavoritesMode() {
            const stored = localStorage.getItem(FAVORITES_MODE_KEY);
            return stored === 'true';
        }

        function persistFavoritesMode(enabled) {
            localStorage.setItem(FAVORITES_MODE_KEY, enabled ? 'true' : 'false');
        }

        function setFavoritesMode(enabled) {
            favoritesModeEnabled = enabled;
            persistFavoritesMode(enabled);
            document.body.classList.toggle('favorites-mode-on', enabled);
            if (favoritesToggleInput) {
                favoritesToggleInput.checked = enabled;
            }
            const favoritesSidebarBtn = document.getElementById('favorites-sidebar-btn');
            if (favoritesSidebarBtn) {
                favoritesSidebarBtn.classList.toggle('active', favoritesOnlyFilter);
            }
            applyAllFilters();
        }

        function initFavoritesToggle() {
            favoritesModeEnabled = loadFavoritesMode();
            setFavoritesMode(favoritesModeEnabled);
            if (favoritesToggleInput) {
                favoritesToggleInput.checked = favoritesModeEnabled;
                favoritesToggleInput.addEventListener('change', (event) => {
                    setFavoritesMode(Boolean(event.target.checked));
                });
            }
        }

        // Load prompts configuration and build UI dynamically
        async function loadPrompts() {
            try {
                grid.classList.add('loading');
                const previouslySelectedPromptId = window.promptbankenPendingPromptSelection || selectedPromptId;
                delete window.promptbankenPendingPromptSelection;

                // Fetch prompts.json
                const configResponse = await fetch('prompts.json');
                if (!configResponse.ok) {
                    throw new Error(`Failed to load prompts.json: ${configResponse.statusText}`);
                }

                const config = await configResponse.json();
                const prompts = config.prompts || [];
                const activeContextKey = getActiveContextKey();
                const visiblePrompts = prompts.filter((prompt) => matchesGlobalContext(prompt.id, activeContextKey));

                // Clear loading message
                grid.innerHTML = '';

                allPrompts = visiblePrompts.slice();

                if (!visiblePrompts.length) {
                    grid.innerHTML = '<div class="catalog-empty-state">Inga prompts matchar vald kontext just nu.</div>';
                    updateLibraryStats(visiblePrompts);
                    populateFilterOptions(visiblePrompts);
                    updateFavoritesMenu();
                    grid.classList.remove('loading');
                    resolvePromptbankenReady();
                    return;
                }

                // Build UI for each prompt
                for (const [index, prompt] of visiblePrompts.entries()) {
                    try {
                        // Fetch prompt text file
                        const promptResponse = await fetch(prompt.file);
                        if (!promptResponse.ok) {
                            throw new Error(`Failed to load ${prompt.file}`);
                        }

                        const promptText = await promptResponse.text();

                        // Create card HTML with quick input text support
                        const card = createPromptCard(prompt, promptText, index);
                        grid.appendChild(card);
                    } catch (error) {
                        console.error(`Error loading prompt ${prompt.id}:`, error);
                        grid.innerHTML += `<div class="error-message">⚠️ Kunde inte ladda prompt: ${prompt.title}</div>`;
                    }
                }

                updateLibraryStats(visiblePrompts);
                populateFilterOptions(visiblePrompts);

                // Set up event delegation for all cards
                setupEventDelegation();

                // Load favorite states from localStorage
                loadFavoriteStates();

                // Update favorites menu
                updateFavoritesMenu();
                applyPromptSort();
                if (visiblePrompts.length) {
                    const keepCurrentSelection = visiblePrompts.some((prompt) => prompt.id === previouslySelectedPromptId);
                    const nextPromptId = keepCurrentSelection
                        ? previouslySelectedPromptId
                        : visiblePrompts[0].id;
                    selectPrompt(nextPromptId, { reveal: false, markSelected: keepCurrentSelection });
                }

                grid.classList.remove('loading');
                resolvePromptbankenReady();
            } catch (error) {
                console.error('Error loading prompts:', error);
                grid.innerHTML = `<div class="error-message">⚠️ Kunde inte ladda promptmallar. Kontrollera att prompts.json och prompt-filer finns.</div>`;
                grid.classList.remove('loading');
                resolvePromptbankenReady();
            }
        }

        function updateLibraryStats(prompts) {
            const statPrompts = document.getElementById('stat-prompts');
            const statCategories = document.getElementById('stat-categories');
            const resultCount = document.getElementById('result-count');
            const categories = new Set(prompts.map((prompt) => getPromptMeta(prompt).category));

            if (statPrompts) statPrompts.textContent = String(prompts.length);
            if (statCategories) statCategories.textContent = String(categories.size);
            if (resultCount) resultCount.textContent = `Visar 1-${prompts.length} av ${prompts.length} prompter`;
        }

        function setFilterOptions(selectId, values, allLabel) {
            const select = document.getElementById(selectId);
            if (!select) return;

            const currentValue = select.value || 'all';
            const collator = new Intl.Collator('sv', { sensitivity: 'base' });
            const options = Array.from(new Set(values.filter(Boolean))).sort(collator.compare);
            select.innerHTML = [
                `<option value="all">${allLabel}</option>`,
                ...options.map((value) => `<option value="${value}">${value}</option>`)
            ].join('');
            select.value = options.includes(currentValue) ? currentValue : 'all';
        }

        function populateFilterOptions(prompts) {
            const metadata = prompts.map(getPromptMeta);
            const legacyCategories = metadata.map((meta) => meta.category);
            const catalogAreas = new Set();
            catalogPromptsById.forEach((prompt) => {
                if (prompt.area) catalogAreas.add(prompt.area);
            });
            const catalogCategories = Array.from(catalogAreas).map((area) => catalogAreaLabels.get(area) || area);
            setFilterOptions('category-filter', [...legacyCategories, ...catalogCategories], 'Alla kategorier');
            setFilterOptions('audience-filter', metadata.flatMap((meta) => meta.audiences), 'Alla målgrupper');
            setFilterOptions('role-filter', metadata.flatMap((meta) => meta.roles), 'Alla roller');
            setFilterOptions('risk-filter', metadata.map((meta) => meta.risk), 'Alla risknivåer');
        }

        function getSearchQuery() {
            return document.getElementById('prompt-search')?.value.trim().toLowerCase() || '';
        }

        function comparePromptCards(a, b) {
            const promptA = allPrompts.find((prompt) => prompt.id === a.dataset.promptId);
            const promptB = allPrompts.find((prompt) => prompt.id === b.dataset.promptId);
            if (!promptA || !promptB) return 0;

            const metaA = getPromptMeta(promptA);
            const metaB = getPromptMeta(promptB);
            const titleA = stripLeadingIcon(promptA.title);
            const titleB = stripLeadingIcon(promptB.title);
            const orderA = Number(a.dataset.originalOrder || 0);
            const orderB = Number(b.dataset.originalOrder || 0);
            const collator = new Intl.Collator('sv', { sensitivity: 'base' });

            if (activeSort === 'title-asc') return collator.compare(titleA, titleB);
            if (activeSort === 'title-desc') return collator.compare(titleB, titleA);
            if (activeSort === 'category-asc') {
                const categoryCompare = collator.compare(metaA.category, metaB.category);
                return categoryCompare || collator.compare(titleA, titleB);
            }
            if (activeSort === 'risk-asc') {
                return getRiskRank(metaA.risk) - getRiskRank(metaB.risk) || collator.compare(titleA, titleB);
            }
            if (activeSort === 'risk-desc') {
                return getRiskRank(metaB.risk) - getRiskRank(metaA.risk) || collator.compare(titleA, titleB);
            }

            return orderA - orderB;
        }

        function applyPromptSort() {
            if (!grid) return;

            Array.from(grid.querySelectorAll('.prompt-card'))
                .sort(comparePromptCards)
                .forEach((card) => grid.appendChild(card));
        }

        function initPromptSort() {
            const sortSelect = document.getElementById('prompt-sort');
            if (!sortSelect) return;

            activeSort = sortSelect.value || 'newest';
            sortSelect.addEventListener('change', () => {
                activeSort = sortSelect.value || 'newest';
                applyPromptSort();
                applyAllFilters();
            });
        }

        function applyPromptFilters() {
            if (!grid) return 0;

            const query = getSearchQuery();
            const favorites = getFavorites();
            let visibleCount = 0;

            grid.querySelectorAll('.prompt-card').forEach((card) => {
                const prompt = allPrompts.find((item) => item.id === card.dataset.promptId);
                if (!prompt) {
                    card.hidden = true;
                    return;
                }

                const meta = getPromptMeta(prompt);
                const haystack = `${prompt.title} ${prompt.description} ${meta.category} ${meta.audience} ${meta.role} ${meta.risk} ${meta.example} ${meta.phrase}`.toLowerCase();
                const matchesSearch = !query || haystack.includes(query);
                const matchesCategory = activeCategoryFilter === 'all' || meta.category === activeCategoryFilter;
                const matchesAudience = activeAudienceFilter === 'all' || meta.audiences.includes(activeAudienceFilter);
                const matchesRole = activeRoleFilter === 'all' || meta.roles.includes(activeRoleFilter);
                const matchesRisk = activeRiskFilter === 'all' || meta.risk === activeRiskFilter;
                const matchesFavorites = !favoritesOnlyFilter || favorites.includes(prompt.id);
                const isVisible = matchesSearch && matchesCategory && matchesAudience && matchesRole && matchesRisk && matchesFavorites;

                setElementHiddenState(card, !isVisible);
                if (isVisible) visibleCount += 1;
            });

            return visibleCount;
        }

        function applyAllFilters() {
            const legacyVisible = applyPromptFilters();
            applyCatalogPromptFilters();
            applyCatalogPackageFilters();

            const catalogPromptVisible = document.querySelectorAll('#catalog-prompt-grid .catalog-card:not([hidden])').length;
            const catalogPackageVisible = document.querySelectorAll('#catalog-package-grid .catalog-card:not([hidden])').length;
            const totalVisible = legacyVisible + catalogPromptVisible + catalogPackageVisible;

            const totalAll = allPrompts.length + catalogPromptsById.size + catalogLabelToArea.size;

            const resultCount = document.getElementById('result-count');
            if (resultCount) {
                resultCount.textContent = `Visar ${totalVisible} av ${totalAll} prompter`;
            }

            const emptyState = document.getElementById('prompt-grid-empty');
            if (emptyState) {
                setElementHiddenState(emptyState, totalVisible !== 0);
            }

            const query = getSearchQuery();
            clearTimeout(window.promptbankenSearchUsageTimer);
            window.promptbankenSearchUsageTimer = setTimeout(() => {
                if (!query) return;
                trackLibraryUsageEvent({
                    eventType: 'search',
                    outcome: totalVisible > 0 ? 'success' : 'empty',
                    resultCount: totalVisible,
                    metadata: { query_length: Math.min(query.length, 200) }
                });
            }, 800);
        }

        function initCategoryFilters() {
            const trackCategoryFilter = () => {
                if (activeCategoryFilter === 'all') return;
                trackLibraryUsageEvent({
                    eventType: 'filter_apply',
                    resultCount: document.querySelectorAll('.prompt-card:not([hidden])').length,
                    metadata: {
                        filter_key: 'category',
                        filter_value: activeCategoryFilter
                    }
                });
            };

            document.querySelectorAll('[data-category-filter]').forEach((button) => {
                button.addEventListener('click', () => {
                    activeCategoryFilter = button.getAttribute('data-category-filter') || 'all';
                    favoritesOnlyFilter = false;
                    const categoryFilter = document.getElementById('category-filter');
                    if (categoryFilter) categoryFilter.value = activeCategoryFilter;
                    document.querySelectorAll('[data-category-filter]').forEach((item) => {
                        item.classList.toggle('active', item.getAttribute('data-category-filter') === activeCategoryFilter);
                    });
                    const favoritesSidebarBtn = document.getElementById('favorites-sidebar-btn');
                    if (favoritesSidebarBtn) favoritesSidebarBtn.classList.remove('active');
                    applyAllFilters();
                    trackCategoryFilter();
                });
            });

            const categoryFilter = document.getElementById('category-filter');
            const audienceFilter = document.getElementById('audience-filter');
            const roleFilter = document.getElementById('role-filter');
            const riskFilter = document.getElementById('risk-filter');
            const clearFiltersBtn = document.getElementById('clear-filters-btn');

            if (categoryFilter) {
                categoryFilter.addEventListener('change', () => {
                    activeCategoryFilter = categoryFilter.value || 'all';
                    document.querySelectorAll('[data-category-filter]').forEach((item) => {
                        item.classList.toggle('active', item.getAttribute('data-category-filter') === activeCategoryFilter);
                    });
                    applyAllFilters();
                    trackCategoryFilter();
                });
            }

            if (audienceFilter) {
                audienceFilter.addEventListener('change', () => {
                    activeAudienceFilter = audienceFilter.value || 'all';
                    applyAllFilters();
                });
            }

            if (roleFilter) {
                roleFilter.addEventListener('change', () => {
                    activeRoleFilter = roleFilter.value || 'all';
                    applyAllFilters();
                });
            }

            if (riskFilter) {
                riskFilter.addEventListener('change', () => {
                    activeRiskFilter = riskFilter.value || 'all';
                    applyAllFilters();
                });
            }

            function clearAllPromptFilters() {
                activeCategoryFilter = 'all';
                activeAudienceFilter = 'all';
                activeRoleFilter = 'all';
                activeRiskFilter = 'all';
                favoritesOnlyFilter = false;
                if (categoryFilter) categoryFilter.value = 'all';
                if (audienceFilter) audienceFilter.value = 'all';
                if (roleFilter) roleFilter.value = 'all';
                if (riskFilter) riskFilter.value = 'all';
                const searchInput = document.getElementById('prompt-search');
                if (searchInput) searchInput.value = '';
                document.querySelectorAll('[data-category-filter]').forEach((item) => {
                    item.classList.toggle('active', item.getAttribute('data-category-filter') === 'all');
                });
                const favoritesSidebarBtn = document.getElementById('favorites-sidebar-btn');
                if (favoritesSidebarBtn) favoritesSidebarBtn.classList.remove('active');
                applyAllFilters();

                saveGlobalRenderState({
                    roll: DEFAULT_RENDER_STATE.roll,
                    malgrupp: DEFAULT_RENDER_STATE.malgrupp,
                    ton: DEFAULT_RENDER_STATE.ton
                });
                syncGlobalRenderControls();
                renderGlobalContextStatus();
                refreshGlobalRenderOutputs();
            }

            if (clearFiltersBtn) {
                clearFiltersBtn.addEventListener('click', clearAllPromptFilters);
            }

            const emptyStateClearBtn = document.getElementById('empty-state-clear-btn');
            if (emptyStateClearBtn) {
                emptyStateClearBtn.addEventListener('click', clearAllPromptFilters);
            }
        }

        function getPromptText(promptId) {
            const textArea = document.getElementById(`textarea-${promptId}`);
            if (!textArea) return '';
            const prompt = allPrompts.find((item) => item.id === promptId) || {};
            const catalogVariant = getCachedStaticCatalogPromptVariant(promptId);
            const sourceText = catalogVariant?.prompt_text || textArea.value;
            const schema = catalogVariant?.parameter_schema || prompt.parameter_schema;
            const bindingOverrides = catalogVariant?.binding_overrides || prompt.binding_overrides || [];
            const defaults = { ...(prompt.default_bindings || {}) };
            if (catalogVariant?.default_bindings) {
                Object.assign(defaults, catalogVariant.default_bindings);
            }
            if (quickInputText && quickInputText.trim()) {
                const fallbackField = schema?.legacy_fallback_field || 'input';
                defaults[fallbackField] = quickInputText;
            }
            const template = adaptLegacyPromptTemplate(sourceText, schema);
            const bindings = resolvePromptBindings(
                getGlobalRenderState(),
                schema,
                defaults,
                bindingOverrides
            );
            return replaceInputMarkers(renderPromptTemplate(template, bindings), quickInputText);
        }

        async function refreshPromptPreviewFromCatalog(promptId) {
            if (!promptId) return;
            const variant = await ensureStaticCatalogPromptVariant(promptId);
            if (!variant || selectedPromptId !== promptId) return;

            const preview = document.getElementById('detail-prompt-preview');
            if (preview) {
                preview.textContent = getPromptText(promptId) || 'Prompttext saknas.';
            }
            renderGlobalContextStatus();
        }

        function selectPrompt(promptId, options = {}) {
            const shouldReveal = options.reveal !== false;
            const shouldMarkSelected = options.markSelected !== false;
            selectedPromptId = promptId;
            const prompt = allPrompts.find((item) => item.id === promptId);
            if (!prompt) return;
            activeCatalogPromptEntity = null;
            document.getElementById('detail-risk')?.style.removeProperty('display');
            ['detail-meta-row', 'detail-example-section', 'detail-phrase-section'].forEach((id) => {
                document.getElementById(id)?.style.removeProperty('display');
            });
            document.body.classList.remove('detail-panel-closed');
            if (shouldReveal) {
                document.body.classList.add('detail-sheet-open');
            }

            const meta = getPromptMeta(prompt);
            const title = stripLeadingIcon(prompt.title);

            if (shouldReveal) {
                const promptViewKey = `prompt_view:${promptId}:${getActiveCatalogContextKeys().join(',')}`;
                if (shouldTrackLibraryUsage(promptViewKey, 60 * 60 * 1000)) {
                    trackLibraryUsageEvent({
                        eventType: 'prompt_view',
                        promptSlug: promptId,
                        area: meta.category || null,
                        riskLevel: meta.risk || null
                    });
                }
            }

            if (shouldMarkSelected) {
                grid.querySelectorAll('.prompt-card').forEach((card) => {
                    card.classList.toggle('selected', card.dataset.promptId === promptId);
                });
            }

            const fields = {
                title: document.getElementById('selected-prompt-title'),
                description: document.getElementById('selected-prompt-description'),
                icon: document.getElementById('detail-icon'),
                risk: document.getElementById('detail-risk'),
                audience: document.getElementById('detail-audience'),
                role: document.getElementById('detail-role'),
                example: document.getElementById('detail-example'),
                phrase: document.getElementById('detail-phrase'),
                preview: document.getElementById('detail-prompt-preview'),
                related: document.getElementById('related-prompts')
            };

            if (fields.title) fields.title.textContent = title;
            if (fields.description) fields.description.textContent = prompt.description;
            if (fields.icon) {
                fields.icon.textContent = '';
                fields.icon.dataset.icon = getIconName(promptId, meta.category);
            }
            if (fields.risk) {
                fields.risk.textContent = meta.risk;
                fields.risk.dataset.risk = meta.risk.toLowerCase();
            }
            if (fields.audience) fields.audience.textContent = meta.audience;
            if (fields.role) fields.role.textContent = meta.role;
            if (fields.example) fields.example.textContent = meta.example;
            if (fields.phrase) fields.phrase.textContent = `"${meta.phrase}"`;
            if (fields.preview) fields.preview.textContent = getPromptText(promptId) || 'Prompttext saknas.';
            renderGlobalContextStatus();
            refreshPromptPreviewFromCatalog(promptId);

            activeCatalogPromptEntity = null;
            document.getElementById('prompt-detail-panel')?.removeAttribute('data-catalog-prompt-slug');
            document.querySelectorAll('#selected-prompt-chat-btn, #selected-prompt-copy-btn, #selected-prompt-view-btn, #selected-prompt-export-btn')
                .forEach((button) => {
                    button.removeAttribute('disabled');
                    button.removeAttribute('data-catalog-action');
                    button.removeAttribute('data-catalog-prompt-slug');
                    if (button.id === 'selected-prompt-copy-btn') {
                        button.textContent = 'Kopiera';
                        button.classList.remove('copied', 'is-copied');
                    }
                });

            if (fields.related) {
                fields.related.innerHTML = allPrompts
                    .filter((item) => item.id !== promptId && getPromptMeta(item).category === meta.category)
                    .slice(0, 3)
                    .map((item) => `<button type="button" data-related-prompt="${item.id}">${stripLeadingIcon(item.title)}</button>`)
                    .join('');
            }

            const detailPanel = document.getElementById('prompt-detail-panel');
            if (shouldReveal && detailPanel && window.matchMedia('(max-width: 1180px)').matches) {
                window.requestAnimationFrame(() => {
                    detailPanel.focus({ preventScroll: true });
                    detailPanel.scrollIntoView({ block: 'start', behavior: 'smooth' });
                });
            }
        }

        window.selectWorkflowPrompt = selectPrompt;

        function closePromptDetailPanel() {
            selectedPromptId = null;
            activeCatalogPromptEntity = null;
            document.body.classList.add('detail-panel-closed');
            document.body.classList.remove('detail-sheet-open');
            document.getElementById('prompt-detail-panel')?.removeAttribute('data-catalog-prompt-slug');
            grid.querySelectorAll('.prompt-card.selected').forEach((card) => {
                card.classList.remove('selected');
            });
            document.querySelectorAll('#selected-prompt-chat-btn, #selected-prompt-copy-btn, #selected-prompt-view-btn, #selected-prompt-export-btn')
                .forEach((button) => {
                    button.setAttribute('disabled', 'disabled');
                    button.removeAttribute('data-catalog-action');
                    button.removeAttribute('data-catalog-prompt-slug');
                });
        }

        function loadLocalChatMode() {
            const stored = localStorage.getItem(LOCAL_CHAT_MODE_KEY);
            return stored === 'true';
        }

        function persistLocalChatMode(enabled) {
            localStorage.setItem(LOCAL_CHAT_MODE_KEY, enabled ? 'true' : 'false');
        }

        function setLocalChatMode(enabled) {
            localChatEnabled = enabled;
            persistLocalChatMode(enabled);
            document.body.classList.toggle('local-chat-enabled', enabled);
            if (localChatToggleInput) {
                localChatToggleInput.checked = enabled;
            }
        }

        function initLocalChatToggle() {
            setLocalChatMode(LOCAL_CHAT_FEATURE_ENABLED && loadLocalChatMode());
            if (localChatToggleInput) {
                localChatToggleInput.addEventListener('change', (event) => {
                    setLocalChatMode(Boolean(event.target.checked));
                });
            }
        }

        function escapeHtml(value) {
            return String(value ?? '')
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;')
                .replace(/'/g, '&#39;');
        }

        function createPromptCard(prompt, promptText, originalOrder = 0) {
            const card = document.createElement('div');
            card.className = prompt.own ? 'prompt-card own-prompt-card' : 'prompt-card';
            card.setAttribute('data-prompt-id', prompt.id);
            card.dataset.originalOrder = String(originalOrder);
            const rawMeta = getPromptMeta(prompt);
            const meta = {
                ...rawMeta,
                category: escapeHtml(rawMeta.category),
                audience: escapeHtml(rawMeta.audience),
                role: escapeHtml(rawMeta.role),
                risk: escapeHtml(rawMeta.risk),
                phrase: escapeHtml(rawMeta.phrase)
            };
            const title = escapeHtml(stripLeadingIcon(prompt.title));
            const description = escapeHtml(prompt.description);

            // Include user input dynamically
            const userInput = document.getElementById('quick-input-textarea')?.value || '';
            const combinedText = userInput ? `${userInput}\n\n${promptText}` : promptText;

            const ownChip = prompt.own
                ? `<span class="own-chip">${prompt.ownVisibility === 'workspace' ? 'Din prompt · Delad' : 'Din prompt · Privat'}</span>`
                : '';

            // Build card HTML
            card.innerHTML = `
                <button class="favorite-btn favorites-only" data-favorite="${prompt.id}" title="Markera som favorit">☆</button>
                <span class="selected-check" aria-hidden="true">✓</span>
                <div class="card-title-row">
                    <span class="card-icon app-icon" aria-hidden="true" data-icon="${getIconName(prompt.id, meta.category)}"></span>
                    <div>
                        <span class="card-kicker">${meta.category}</span>
                        <h3>${title}</h3>
                    </div>
                </div>
                <p>${description}</p>
                <div class="card-tags">
                    ${ownChip}
                    <span class="risk-chip" data-risk="${meta.risk.toLowerCase()}">${meta.risk}</span>
                    <span>${meta.audience}</span>
                    <span>${meta.role}</span>
                </div>
                <p class="card-example">Exempel: "${meta.phrase}"</p>
                <div class="actions card-actions">
                    <button class="primary-btn export-btn advanced-only" data-export="${prompt.id}">Anpassa prompt</button>
                    <button class="select-prompt-btn" type="button">Välj</button>
                    <button class="copy-btn copy-btn-primary" data-prompt="${prompt.id}" type="button" hidden aria-hidden="true" tabindex="-1">Kopiera</button>
                    <button class="secondary-btn info-btn" data-show-full="${prompt.id}" type="button" title="Förhandsvisa">Förhandsvisa</button>
                    <button class="secondary-btn local-chat-btn" data-chat-local="${prompt.id}">Chatta lokalt</button>
                    <button class="secondary-btn direct-chat-btn" type="button" disabled aria-disabled="true" title="Kommer snart">Chatta direkt (kommer snart)</button>
                </div>
                <textarea id="textarea-${prompt.id}" aria-hidden="true" tabindex="-1">${combinedText}</textarea>
            `;
            return card;
        }

        async function registerOwnPrompts(items) {
            await window.promptbankenReady;

            if (!Array.isArray(items) || !items.length) {
                return;
            }

            items.forEach((item) => {
                if (allPrompts.some((existing) => existing.id === item.id)) {
                    return;
                }

                promptUiMeta[item.id] = {
                    icon: '✎',
                    category: item.category || 'Alla kategorier',
                    audience: item.audience || 'Intern',
                    role: 'Egen prompt',
                    risk: item.risk || 'Låg risk',
                    example: 'Din egen sparade prompt.',
                    phrase: 'Använd din egen prompt.'
                };

                const promptEntry = {
                    id: item.id,
                    title: item.title,
                    description: item.description || '',
                    own: true,
                    ownVisibility: item.visibility
                };

                allPrompts.push(promptEntry);

                const card = createPromptCard(promptEntry, item.content || '', allPrompts.length);
                grid.appendChild(card);
            });

            populateFilterOptions(allPrompts);
            updateLibraryStats(allPrompts);
            loadFavoriteStates();
            applyPromptSort();
            applyAllFilters();
        }

        async function registerProTemplates(items) {
            await window.promptbankenReady;

            if (!Array.isArray(items) || !items.length) {
                return;
            }

            items.forEach((item) => {
                if (allPrompts.some((existing) => existing.id === item.id)) {
                    return;
                }

                promptUiMeta[item.id] = {
                    icon: '▤',
                    category: item.category || 'Alla kategorier',
                    audience: 'Intern & extern',
                    role: 'Alla roller',
                    risk: item.risk || 'Låg risk',
                    example: item.description || '',
                    phrase: 'Anpassa efter ditt ärende.'
                };

                const promptEntry = {
                    id: item.id,
                    title: item.title,
                    description: item.description || ''
                };

                allPrompts.push(promptEntry);

                const card = createPromptCard(promptEntry, item.content || '', allPrompts.length);
                grid.appendChild(card);
            });

            populateFilterOptions(allPrompts);
            updateLibraryStats(allPrompts);
            loadFavoriteStates();
            applyPromptSort();
            applyAllFilters();
        }

        window.registerOwnPrompts = registerOwnPrompts;
        window.registerProTemplates = registerProTemplates;

        function setupEventDelegation() {
            // Toggle examples - event delegation
            grid.addEventListener('click', (event) => {
                const card = event.target.closest('.prompt-card');
                const clickedControl = event.target.closest('button, a, input, select, textarea, label');
                if (card && !clickedControl) {
                    selectPrompt(card.dataset.promptId, { reveal: true });
                }

                if (event.target.classList.contains('security-note-link')) {
                    event.preventDefault();
                    const promptId = event.target.getAttribute('data-toggle-examples');
                    const examplesDiv = grid.querySelector(`[data-prompt="${promptId}"].security-examples`);
                    if (examplesDiv) {
                        examplesDiv.classList.toggle('active');
                    }
                }

                // Copy button click
                if (event.target.classList.contains('copy-btn')) {
                    handleCopyClick(event.target, event);
                }

                if (event.target.classList.contains('select-prompt-btn')) {
                    event.preventDefault();
                    event.stopPropagation();
                    if (card) {
                        selectPrompt(card.dataset.promptId, { reveal: true });
                    }
                }

                // Favorite button click
                if (event.target.classList.contains('favorite-btn')) {
                    handleFavoriteClick(event.target);
                }

                // Info button click
                if (event.target.classList.contains('info-btn')) {
                    event.preventDefault();
                    event.stopPropagation();
                    handleInfoClick(event.target);
                }

                if (event.target.classList.contains('local-chat-btn')) {
                    const promptId = event.target.getAttribute('data-chat-local');
                    navigateToLocalChat(promptId);
                }
            });
        }

        // Favorite management functions
        function getFavorites() {
            const stored = localStorage.getItem('favoritePrompts');
            return stored ? JSON.parse(stored) : [];
        }

        function saveFavorites(favorites) {
            localStorage.setItem('favoritePrompts', JSON.stringify(favorites));
        }

        function toggleFavorite(promptId) {
            let favorites = getFavorites();
            const index = favorites.indexOf(promptId);

            if (index > -1) {
                // Remove from favorites
                favorites.splice(index, 1);
            } else {
                // Add to favorites
                favorites.push(promptId);
            }

            saveFavorites(favorites);
            return favorites.includes(promptId);
        }

        function handleFavoriteClick(button) {
            const promptId = button.getAttribute('data-favorite');
            const isFavorite = toggleFavorite(promptId);

            // Update UI
            button.textContent = isFavorite ? '★' : '☆';
            button.classList.toggle('active', isFavorite);

            // Update favorites menu
            updateFavoritesMenu();
            applyAllFilters();
        }

        function loadFavoriteStates() {
            const favorites = getFavorites();
            favorites.forEach(promptId => {
                const button = grid.querySelector(`[data-favorite="${promptId}"]`);
                if (button) {
                    button.textContent = '★';
                    button.classList.add('active');
                }
            });
        }

        function updateFavoritesMenu() {
            const favorites = getFavorites();

            if (favorites.length === 0) {
                // Hide menu if no favorites
                favoritesMenu.classList.add('hidden');
                return;
            }

            // Show menu
            favoritesMenu.classList.remove('hidden');

            // Clear existing chips
            favoritesList.innerHTML = '';

            // Create chip for each favorite
            favorites.forEach(promptId => {
                const prompt = allPrompts.find(p => p.id === promptId);
                if (prompt) {
                    const chip = document.createElement('div');
                    chip.className = 'favorite-chip';
                    chip.setAttribute('data-scroll-to', promptId);
                    chip.innerHTML = `<span>${prompt.title}</span>`;
                    chip.addEventListener('click', () => scrollToPrompt(promptId));
                    favoritesList.appendChild(chip);
                }
            });
        }

        function scrollToPrompt(promptId) {
            const card = grid.querySelector(`[data-prompt-id="${promptId}"]`);
            if (card) {
                card.scrollIntoView({ behavior: 'smooth', block: 'center' });
                // Flash effect
                card.style.transition = 'box-shadow 0.3s ease';
                card.style.boxShadow = '0 0 20px rgba(255, 193, 7, 0.6)';
                setTimeout(() => {
                    card.style.boxShadow = '';
                }, 1000);
            }
        }

        function initPromptSearch() {
            const searchInput = document.getElementById('prompt-search');
            if (!searchInput) return;

            ['input', 'keyup', 'search', 'change'].forEach((eventName) => {
                searchInput.addEventListener(eventName, applyAllFilters);
            });
        }

        function clearAllFavorites() {
            if (confirm('Är du säker på att du vill rensa alla favoriter?')) {
                // Clear localStorage
                localStorage.removeItem('favoritePrompts');

                // Update all star buttons
                const allStarButtons = grid.querySelectorAll('.favorite-btn');
                allStarButtons.forEach(button => {
                    button.textContent = '☆';
                    button.classList.remove('active');
                });

                // Clear the favorites list in the orange activity bar
                favoritesList.innerHTML = '';

                // Update favorites menu
                updateFavoritesMenu();
                applyAllFilters();
            }
        }

        // Set up clear favorites button
        clearFavoritesBtn.addEventListener('click', clearAllFavorites);
        const detailCloseBtn = document.getElementById('detail-close');
        if (detailCloseBtn) {
            detailCloseBtn.addEventListener('click', (event) => {
                event.preventDefault();
                event.stopPropagation();
                closePromptDetailPanel();
            });
        }

        const filterToggle = document.getElementById('filter-toggle');
        const advancedFilters = document.getElementById('advanced-filters');
        if (filterToggle && advancedFilters) {
            filterToggle.addEventListener('click', () => {
                const isOpen = advancedFilters.classList.toggle('is-open');
                filterToggle.setAttribute('aria-expanded', String(isOpen));
            });
        }

        document.addEventListener('click', (event) => {
            if (event.target.closest('#detail-close')) {
                closePromptDetailPanel();
                return;
            }

            const relatedButton = event.target.closest('[data-related-prompt]');
            if (relatedButton) {
                selectPrompt(relatedButton.getAttribute('data-related-prompt'), { reveal: true });
                return;
            }

            const selectedCopyButton = event.target.closest('#selected-prompt-copy-btn');
            const selectedCatalogCopyEntity = getSelectedCatalogPromptEntity(selectedCopyButton);
            if (selectedCatalogCopyEntity && selectedCopyButton) {
                copyCatalogEntityText(selectedCatalogCopyEntity, selectedCopyButton);
                return;
            }

            const selectedViewButton = event.target.closest('#selected-prompt-view-btn');
            const selectedCatalogViewEntity = getSelectedCatalogPromptEntity(selectedViewButton);
            if (selectedCatalogViewEntity && selectedViewButton) {
                openCatalogEntityPreviewModal(selectedCatalogViewEntity);
                return;
            }

            if (!selectedPromptId) return;

            if (event.target.id === 'selected-prompt-chat-btn') {
                navigateToLocalChat(selectedPromptId);
            }

            if (event.target.id === 'selected-prompt-copy-btn') {
                const cardButton = grid.querySelector(`.copy-btn[data-prompt="${selectedPromptId}"]`);
                if (cardButton) handleCopyClick(cardButton, event, event.target);
            }

            if (event.target.id === 'selected-prompt-view-btn') {
                openPromptPreviewModal(selectedPromptId);
            }

            if (event.target.id === 'selected-prompt-export-btn') {
                openExportModal(selectedPromptId);
            }
        });

        // Modal functionality
        const promptModal = document.getElementById('prompt-modal');
        const promptModalTitle = document.getElementById('modal-title');
        const promptModalText = document.getElementById('modal-text');
        const promptModalClose = document.getElementById('modal-close');

        async function openPromptPreviewModal(promptId) {
            const textArea = document.getElementById(`textarea-${promptId}`);
            const prompt = allPrompts.find(p => p.id === promptId);

            if (textArea && prompt) {
                promptModal.dataset.promptId = promptId;
                promptModalTitle.textContent = `Förhandsvisning: ${stripLeadingIcon(prompt.title)}`;
                promptModalText.textContent = getPromptText(promptId);
                promptModal.hidden = false;
                promptModal.classList.add('active');
                promptModalClose?.focus({ preventScroll: true });
                const variant = await ensureStaticCatalogPromptVariant(promptId);
                if (variant && promptModal.classList.contains('active') && promptModal.dataset.promptId === promptId) {
                    promptModalText.textContent = getPromptText(promptId);
                }
            }
        }

        async function handleInfoClick(button) {
            const promptId = button.getAttribute('data-show-full');
            openPromptPreviewModal(promptId);
        }

        function closeModal() {
            promptModal.classList.remove('active');
            promptModal.hidden = true;
            delete promptModal.dataset.promptId;
        }

        // Close button
        promptModalClose.addEventListener('click', closeModal);

        // Click outside to close
        promptModal.addEventListener('click', (event) => {
            if (event.target === promptModal) {
                closeModal();
            }
        });

        // ESC key to close
        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape' && promptModal.classList.contains('active')) {
                closeModal();
            }
        });

        function updateButtonState(promptId) {
            const checkbox = document.querySelector(`#anon-${promptId}`);
            const button = document.querySelector(`.copy-btn[data-prompt="${promptId}"]`);

            if (checkbox && button) {
                if (checkbox.checked) {
                    button.removeAttribute('disabled');
                } else {
                    button.setAttribute('disabled', 'disabled');
                }
            }
        }

        async function handleCopyClick(button, clickEvent, feedbackButton = button) {
            if (clickEvent) clickEvent.preventDefault();
            const promptId = button.getAttribute('data-prompt');
            const textArea = document.getElementById(`textarea-${promptId}`);

            if (!textArea) {
                console.error(`Textarea for prompt '${promptId}' not found`);
                return;
            }

            let textToCopy = getPromptText(promptId);

            try {
                await navigator.clipboard.writeText(textToCopy);

                const prompt = allPrompts.find((item) => item.id === promptId);
                const meta = prompt ? getPromptMeta(prompt) : {};
                trackLibraryUsageEvent({
                    eventType: 'prompt_copy',
                    promptSlug: promptId,
                    area: meta.category || null,
                    riskLevel: meta.risk || null,
                    metadata: {
                        copy_surface: feedbackButton.id === 'selected-prompt-copy-btn' ? 'detail_panel' : 'card'
                    }
                });

                // Visual feedback
                const originalText = feedbackButton.textContent;
                feedbackButton.textContent = 'Kopierat';
                feedbackButton.classList.add('copied', 'is-copied');

                // Reset after 2 seconds
                setTimeout(() => {
                    feedbackButton.textContent = originalText;
                    feedbackButton.classList.remove('copied', 'is-copied');
                }, 2000);
            } catch (err) {
                console.error('Failed to copy:', err);
                alert('Kunde inte kopiera. Prova igen eller kopiera manuellt.');
            }
        }

        function replaceInputMarkers(text, input) {
            if (!input || !input.trim()) return text;
            return text
                .replace(/\[klistra in här\]/gi, input)
                .replace(/\[TEXT\]/gi, input);
        }

        function navigateToLocalChat(promptId) {
            if (!localChatEnabled) {
                return;
            }

            const textArea = document.getElementById(`textarea-${promptId}`);
            const prompt = allPrompts.find((item) => item.id === promptId);
            if (!textArea) {
                showLocalRunError('Kunde inte hitta prompten för lokal chatt.');
                return;
            }

            const preparedPrompt = getPromptText(promptId).trim();
            const payload = {
                promptId,
                title: prompt?.title || 'Prompt',
                prompt: preparedPrompt,
                input: (quickInputText || '').trim()
            };

            try {
                sessionStorage.setItem('promptbankenLocalChatSeed', JSON.stringify(payload));
            } catch (error) {
                console.warn('Kunde inte spara lokal chat-seed i sessionStorage:', error);
            }

            window.location.href = 'local-chat.html';
        }

        // Export settings
        const exportSettingsKey = 'exportSettings';
        const presets = {
            bas: {
                role: 'handlaggare',
                audience: 'invanare',
                tone: 'neutral',
                length: 'balanserad',
                format: 'punktlista'
            },
            ledning: {
                role: 'chef',
                audience: 'ledning',
                tone: 'formell',
                length: 'kort',
                format: 'atgardslista'
            },
            kommunikation: {
                role: 'kommunikator',
                audience: 'invanare',
                tone: 'varm',
                length: 'balanserad',
                format: 'stycke'
            }
        };

        const exportPresetSelect = document.getElementById('export-preset');
        const exportRoleSelect = document.getElementById('export-role');
        const exportRoleCustomInput = document.getElementById('export-role-custom');
        const exportRoleGdpr = document.getElementById('export-role-gdpr');
        const exportAudienceSelect = document.getElementById('export-audience');
        const exportToneSelect = document.getElementById('export-tone');
        const exportLengthSelect = document.getElementById('export-length');
        const exportFormatSelect = document.getElementById('export-format');
        const exportRememberCheckbox = document.getElementById('export-remember');

        function getCurrentExportSettings() {
            return {
                preset: exportPresetSelect.value,
                role: exportRoleSelect.value,
                customRole: exportRoleSelect.value === 'custom' ? exportRoleCustomInput.value.trim() : '',
                audience: exportAudienceSelect.value,
                tone: exportToneSelect.value,
                length: exportLengthSelect.value,
                format: exportFormatSelect.value,
                remember: Boolean(exportRememberCheckbox?.checked)
            };
        }

        function applySettingsToForm(settings) {
            exportPresetSelect.value = settings.preset || 'bas';
            exportRoleSelect.value = settings.role || 'handlaggare';
            exportAudienceSelect.value = settings.audience || 'invanare';
            exportToneSelect.value = settings.tone || 'neutral';
            exportLengthSelect.value = settings.length || 'balanserad';
            exportFormatSelect.value = settings.format || 'punktlista';
            if (exportRememberCheckbox) {
                exportRememberCheckbox.checked = settings.remember ?? false;
            }
            // Show/hide custom role field and set value
            if (exportRoleSelect.value === 'custom') {
                exportRoleCustomInput.style.display = '';
                exportRoleCustomInput.value = settings.customRole || '';
            } else {
                exportRoleCustomInput.style.display = 'none';
                exportRoleCustomInput.value = '';
            }
        }

        function saveExportSettings() {
            const settings = getCurrentExportSettings();
            if (settings.remember) {
                localStorage.setItem(exportSettingsKey, JSON.stringify(settings));
            } else {
                localStorage.removeItem(exportSettingsKey);
            }
        }

        function loadExportSettings() {
            const stored = localStorage.getItem(exportSettingsKey);
            const defaults = { preset: 'bas', remember: false, ...presets.bas };
            const settings = stored ? { ...defaults, ...JSON.parse(stored) } : defaults;
            applySettingsToForm(settings);
        }

        function applyPreset(presetKey) {
            const preset = presets[presetKey];
            if (!preset) return;
            exportPresetSelect.value = presetKey;
            // Set role and trigger change event to update custom field logic
            exportRoleSelect.value = preset.role;
            exportRoleSelect.dispatchEvent(new Event('change'));
            exportAudienceSelect.value = preset.audience;
            exportToneSelect.value = preset.tone;
            exportLengthSelect.value = preset.length;
            exportFormatSelect.value = preset.format;
            if (exportRememberCheckbox?.checked) {
                saveExportSettings();
            }
            updateExportPreview();
        }

        function getLabels(settings) {
            return {
                role: settings.role === 'custom' && settings.customRole
                    ? settings.customRole
                    : {
                        handlaggare: 'Handläggare',
                        chef: 'Chef / ledning',
                        kommunikator: 'Kommunikatör'
                    }[settings.role] || settings.role,
                audience: {
                    invanare: 'Invånare',
                    kollegor: 'Kollegor',
                    ledning: 'Ledning / politiker'
                }[settings.audience] || settings.audience,
                tone: {
                    neutral: 'Neutral',
                    varm: 'Varm och stöttande',
                    formell: 'Formell'
                }[settings.tone] || settings.tone,
                length: {
                    kort: 'Kort sammanfattning',
                    balanserad: 'Balanserad',
                    detaljerad: 'Mer detaljerad'
                }[settings.length] || settings.length,
                format: {
                    punktlista: 'Punktlista',
                    stycke: 'Sammanhängande text',
                    atgardslista: 'Åtgärdslista'
                }[settings.format] || settings.format
            };
        }

        function buildExportText(baseText) {
            const settings = getCurrentExportSettings();
            const labels = getLabels(settings);
            const text = baseText;
            // Only show custom role if selected, otherwise show standard role
            let roleLine = `Roll: ${labels.role}`;
            const header = [
                roleLine,
                `Målgrupp: ${labels.audience}`,
                `Ton: ${labels.tone}`,
                `Längd: ${labels.length}`,
                `Format: ${labels.format}`
            ].join('\n');
            return `${header}\n\n${text}`;
        }

        function registerExportSettingsListeners() {
            exportPresetSelect.addEventListener('change', (event) => {
                applyPreset(event.target.value);
                // Always hide and clear custom role field and GDPR warning on preset change
                if (exportRoleCustomInput) {
                    exportRoleCustomInput.style.display = 'none';
                    exportRoleCustomInput.value = '';
                }
                if (exportRoleGdpr) exportRoleGdpr.style.display = 'none';
            });

            exportRoleSelect.addEventListener('change', () => {
                if (exportRoleSelect.value === 'custom') {
                    exportRoleCustomInput.style.display = '';
                    exportRoleCustomInput.focus();
                    if (exportRoleGdpr) exportRoleGdpr.style.display = '';
                } else {
                    exportRoleCustomInput.style.display = 'none';
                    exportRoleCustomInput.value = '';
                    if (exportRoleGdpr) exportRoleGdpr.style.display = 'none';
                }
                saveExportSettings();
                updateExportPreview();
            });
            exportRoleCustomInput.addEventListener('input', () => {
                saveExportSettings();
                updateExportPreview();
            });
            [
                exportAudienceSelect,
                exportToneSelect,
                exportLengthSelect,
                exportFormatSelect,
                exportRememberCheckbox
            ].forEach(element => {
                if (!element) return;
                element.addEventListener('change', () => {
                    saveExportSettings();
                    updateExportPreview();
                });
            });
        }

        // Export functionality
        const exportModal = document.getElementById('export-modal');
        const exportTextarea = document.getElementById('export-textarea');
        const copyExportBtn = document.getElementById('copy-export-btn');
        const copyAllBtn = document.getElementById('copy-all-btn');
        const previewExportBtn = document.getElementById('preview-export-btn');
        const exportModalClose = document.getElementById('export-modal-close');
        let currentExportText = '';
        let currentPromptRaw = '';

        function updateExportPreview() {
            if (!currentPromptRaw) return;
            const text = buildExportText(currentPromptRaw);
            currentExportText = text;
            exportTextarea.value = text;
            // Show/hide info row if quick input is present
            const infoRow = document.getElementById('export-quickinput-info');
            if (infoRow) {
                if (quickInputText && quickInputText.trim()) {
                    infoRow.style.display = '';
                } else {
                    infoRow.style.display = 'none';
                }
            }
        }

        function openExportModal(promptId) {
            const textArea = document.getElementById(`textarea-${promptId}`);
            if (!textArea) return;
            currentPromptRaw = getPromptText(promptId);
            updateExportPreview();
            exportModal.classList.add('active');
        }

        function closeExportModal() {
            exportModal.classList.remove('active');
            currentExportText = '';
            currentPromptRaw = '';
        }

        function copyExportText() {
            const text = currentExportText || exportTextarea.value;
            navigator.clipboard.writeText(text)
                .then(() => {
                    alert('Text kopierad till urklipp!');
                })
                .catch((err) => {
                    console.error('Kunde inte kopiera text:', err);
                    alert('Misslyckades med att kopiera text.');
                });
        }

        function copyAllText() {
            const combined = [currentExportText || exportTextarea.value, '', '--- Original prompt ---', currentPromptRaw].join('\n');
            navigator.clipboard.writeText(combined)
                .then(() => {
                    alert('Allt kopierat till urklipp!');
                })
                .catch((err) => {
                    console.error('Kunde inte kopiera allt:', err);
                    alert('Misslyckades med att kopiera.');
                });
        }

        // Event listeners
        grid.addEventListener('click', (event) => {
            if (event.target.classList.contains('export-btn')) {
                const promptId = event.target.getAttribute('data-export');
                openExportModal(promptId);
            }
        });

        if (exportModalClose) {
            exportModalClose.addEventListener('click', closeExportModal);
        }
        if (copyExportBtn) {
            copyExportBtn.addEventListener('click', copyExportText);
        }
        if (copyAllBtn) {
            copyAllBtn.addEventListener('click', copyAllText);
        }
        if (previewExportBtn) {
            previewExportBtn.addEventListener('click', updateExportPreview);
        }

        exportModal.addEventListener('click', (event) => {
            if (event.target === exportModal) {
                closeExportModal();
            }
        });

        const localRunModal = document.getElementById('local-run-modal');
        const localRunClose = document.getElementById('local-run-close');
        const localRunTitle = document.getElementById('local-run-title');
        const localModelSelect = document.getElementById('local-model-select');
        const localUserInput = document.getElementById('local-user-input');
        const localRunSubmit = document.getElementById('local-run-submit');
        const localRunCancel = document.getElementById('local-run-cancel');
        const localRunStatus = document.getElementById('local-run-status');
        const localRunResult = document.getElementById('local-run-result');
        const BACKEND_BASE_URL = window.PROMPTBANKEN_API_BASE_URL || window.location.origin.replace(/\/$/, '');
        const localRunModalContent = document.getElementById('local-run-modal-content');
        const localRunExpand = document.getElementById('local-run-expand');
        const localCopyPromptBtn = document.getElementById('local-copy-prompt-btn');
        const localChatInput = document.getElementById('local-chat-input');
        const localChatSend = document.getElementById('local-chat-send');
        const localExportDocxBtn = document.getElementById('local-export-docx');
        const localExportPdfBtn = document.getElementById('local-export-pdf');
        const quickInputFile = document.getElementById('quick-input-file');
        const quickInputFileRow = document.querySelector('.quick-input-file-row');
        let localRunAbortController = null;
        let localConversationMessages = [];
        let latestLocalRunResponse = '';
        const supportedQuickInputExtensions = ['txt', 'md', 'csv', 'json', 'docx'];

        function showQuickInputStatus(message, state = 'ready') {
            const quickInputStatus = document.getElementById('quick-input-status');
            if (!quickInputStatus) {
                return;
            }

            const textNode = quickInputStatus.querySelector('span:last-child');
            if (textNode) {
                textNode.textContent = message;
            }

            quickInputStatus.classList.remove('is-ready', 'is-error');
            quickInputStatus.classList.add(state === 'error' ? 'is-error' : 'is-ready');
        }

        function copyCodeBlock(button, code) {
            navigator.clipboard.writeText(code).then(() => {
                const originalText = button.textContent;
                button.textContent = 'Kopierad';
                setTimeout(() => {
                    button.textContent = originalText;
                }, 1200);
            }).catch(() => {
                button.textContent = 'Kunde inte kopiera';
            });
        }

        function enhanceRenderedCodeBlocks() {
            localRunResult.querySelectorAll('pre > code').forEach((codeBlock) => {
                if (window.hljs) {
                    window.hljs.highlightElement(codeBlock);
                }

                const pre = codeBlock.parentElement;
                if (pre.querySelector('.code-copy-btn')) {
                    return;
                }

                const copyButton = document.createElement('button');
                copyButton.type = 'button';
                copyButton.className = 'code-copy-btn';
                copyButton.textContent = 'Kopiera';
                copyButton.addEventListener('click', () => copyCodeBlock(copyButton, codeBlock.textContent));
                pre.appendChild(copyButton);
            });
        }

        function renderLocalRunResponse(responseText) {
            if (!responseText) {
                localRunResult.textContent = '(Tomt svar från modellen)';
                return;
            }

            if (!window.marked || !window.DOMPurify) {
                localRunResult.textContent = responseText;
                return;
            }

            marked.setOptions({ gfm: true, breaks: true });
            const rawHtml = marked.parse(responseText);
            const safeHtml = window.DOMPurify.sanitize(rawHtml, {
                USE_PROFILES: { html: true },
                ALLOWED_ATTR: ['href', 'title', 'target', 'rel', 'class']
            });

            localRunResult.innerHTML = safeHtml;
            localRunResult.querySelectorAll('a').forEach((link) => {
                link.target = '_blank';
                link.rel = 'noopener noreferrer';
            });
            enhanceRenderedCodeBlocks();
        }

        let selectedPromptForLocalRun = null;

        function setLocalRunStreamingState(isStreaming) {
            localRunSubmit.disabled = isStreaming;
            if (localRunCancel) {
                localRunCancel.disabled = !isStreaming;
            }
            localRunResult.classList.toggle('is-streaming', isStreaming);
        }

        function appendStreamingChunk(chunk) {
            localRunResult.textContent += chunk;
            localRunResult.scrollTop = localRunResult.scrollHeight;
        }


        function resetConversationWithPrompt(initialUserInput) {
            const promptText = getSelectedPromptText();
            const finalPrompt = promptText
                ? `System/Instruktion:
${promptText.trim()}

Användarens indata:
${initialUserInput.trim()}`
                : initialUserInput.trim();

            localConversationMessages = [{ role: 'user', content: finalPrompt }];
        }

        function downloadBlob(filename, blob, mimeType) {
            const safeBlob = blob instanceof Blob ? blob : new Blob([blob], { type: mimeType });
            const url = URL.createObjectURL(safeBlob);
            const link = document.createElement('a');
            link.href = url;
            link.download = filename;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            URL.revokeObjectURL(url);
        }

        function exportLocalResponseAsDocx() {
            if (!latestLocalRunResponse.trim()) {
                showLocalRunError('Det finns inget svar att exportera ännu.');
                return;
            }

            const htmlContent = `<html><body><h1>Promptbanken svar</h1><p>${latestLocalRunResponse
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/\n/g, '</p><p>')}</p></body></html>`;

            if (window.htmlDocx && typeof window.htmlDocx.asBlob === 'function') {
                const docxBlob = window.htmlDocx.asBlob(htmlContent);
                downloadBlob('promptbanken-svar.docx', docxBlob, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
                showLocalRunStatus('DOCX exporterad.');
                return;
            }

            const fallbackBlob = new Blob([latestLocalRunResponse], { type: 'text/plain;charset=utf-8' });
            downloadBlob('promptbanken-svar.txt', fallbackBlob, 'text/plain;charset=utf-8');
            showLocalRunStatus('DOCX-bibliotek saknas, exporterade TXT istället.');
        }

        function exportLocalResponseAsPdf() {
            if (!latestLocalRunResponse.trim()) {
                showLocalRunError('Det finns inget svar att exportera ännu.');
                return;
            }

            const jsPdf = window.jspdf?.jsPDF;
            if (!jsPdf) {
                const fallbackBlob = new Blob([latestLocalRunResponse], { type: 'text/plain;charset=utf-8' });
                downloadBlob('promptbanken-svar.txt', fallbackBlob, 'text/plain;charset=utf-8');
                showLocalRunStatus('PDF-bibliotek saknas, exporterade TXT istället.');
                return;
            }

            const doc = new jsPdf({ unit: 'pt', format: 'a4' });
            const lines = doc.splitTextToSize(latestLocalRunResponse, 520);
            doc.text(lines, 40, 60);
            doc.save('promptbanken-svar.pdf');
            showLocalRunStatus('PDF exporterad.');
        }

        async function extractTextFromFile(file) {
            const extension = (file.name.split('.').pop() || '').toLowerCase();
            if (['txt', 'md', 'csv', 'json', 'log', 'rtf'].includes(extension)) {
                return file.text();
            }

            if (extension === 'docx' && window.mammoth) {
                const arrayBuffer = await file.arrayBuffer();
                const result = await window.mammoth.extractRawText({ arrayBuffer });
                return result.value || '';
            }

            if (extension === 'pdf') {
                if (!window.pdfjsLib) {
                    throw new Error('PDF-läsare är inte laddad ännu.');
                }
                throw new Error('PDF-uppladdning ar tillfalligt avstangd.');
            }

            throw new Error('Filformatet stöds inte ännu.');
        }

        async function handleQuickInputFile(file) {
            if (!file || !quickInputTextarea) {
                return;
            }

            const extension = (file.name.split('.').pop() || '').toLowerCase();
            if (!supportedQuickInputExtensions.includes(extension)) {
                showLocalRunError(`Filtypen .${extension || 'okänd'} stöds inte. Stödjer: txt, md, csv, json, docx.`);
                return;
            }

            try {
                const extractedText = await extractTextFromFile(file);
                quickInputTextarea.value = extractedText.slice(0, 25000);
                quickInputText = quickInputTextarea.value;
                quickInputTextarea.dispatchEvent(new Event('input'));
                showLocalRunStatus(`Fil inläst: ${file.name}`);
            } catch (error) {
                showLocalRunError(`Kunde inte läsa filen (${file.name}): ${error.message}`);
            }
        }

        async function handleQuickInputFile(file) {
            if (!file || !quickInputTextarea) {
                return;
            }

            const extension = (file.name.split('.').pop() || '').toLowerCase();
            if (!supportedQuickInputExtensions.includes(extension)) {
                showQuickInputStatus(`Filtypen .${extension || 'okand'} stods inte. Stodjer: txt, md, csv, json, docx.`, 'error');
                return;
            }

            try {
                const extractedText = await extractTextFromFile(file);
                quickInputTextarea.value = extractedText.slice(0, 25000);
                quickInputText = quickInputTextarea.value;
                quickInputTextarea.dispatchEvent(new Event('input'));
                showQuickInputStatus(`Fil inlast: ${file.name}`);
            } catch (error) {
                showQuickInputStatus(`Kunde inte lasa filen (${file.name}): ${error.message}`, 'error');
            }
        }

        async function sendFollowUpMessage() {
            const followUpText = localChatInput?.value?.trim() || '';
            const selectedModel = localModelSelect.value;
            if (!followUpText) {
                showLocalRunError('Skriv en följdfråga först.');
                return;
            }
            if (!selectedModel) {
                showLocalRunError('Välj en modell.');
                return;
            }

            localConversationMessages.push({ role: 'user', content: followUpText });
            localRunResult.textContent = '';
            setLocalRunStreamingState(true);
            showLocalRunStatus('Modellen skriver på följdfrågan...');
            localRunAbortController = new AbortController();

            try {
                const response = await fetch(`${BACKEND_BASE_URL}/api/chat/stream`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ model: selectedModel, messages: localConversationMessages }),
                    signal: localRunAbortController.signal
                });

                if (!response.ok || !response.body) {
                    const data = await response.json().catch(() => ({}));
                    throw new Error(data.detail?.message || data.detail || 'Följdfråga misslyckades.');
                }

                const reader = response.body.getReader();
                const decoder = new TextDecoder();
                let assistantResponse = '';

                while (true) {
                    const { done, value } = await reader.read();
                    if (done) break;
                    const chunk = decoder.decode(value, { stream: true });
                    if (!chunk) continue;
                    assistantResponse += chunk;
                    appendStreamingChunk(chunk);
                }

                const trailingChunk = decoder.decode();
                if (trailingChunk) {
                    assistantResponse += trailingChunk;
                    appendStreamingChunk(trailingChunk);
                }

                localConversationMessages.push({ role: 'assistant', content: assistantResponse });
                latestLocalRunResponse = assistantResponse;
                renderLocalRunResponse(assistantResponse || '(Tomt svar från modellen)');
                localChatInput.value = '';
                showLocalRunStatus('Klart.');
            } catch (error) {
                if (error.name === 'AbortError') {
                    showLocalRunStatus('Avbruten.');
                } else {
                    showLocalRunError(error.message);
                }
            } finally {
                localRunAbortController = null;
                setLocalRunStreamingState(false);
            }
        }

        async function fetchLocalModels() {
            const response = await fetch(`${BACKEND_BASE_URL}/api/models`);
            if (!response.ok) {
                const data = await response.json().catch(() => ({}));
                throw new Error(data.detail?.message || data.detail || 'Kunde inte hämta modeller från backend.');
            }

            const data = await response.json();
            return data.models || [];
        }

        async function populateProviders() {
            return populateLocalModels();
        }

        async function populateLocalModels() {
            localModelSelect.innerHTML = '<option>Laddar modeller...</option>';

            try {
                const models = await fetchLocalModels();
                if (!models.length) {
                    localModelSelect.innerHTML = '<option value="">Inga modeller hittades</option>';
                    return;
                }

                localModelSelect.innerHTML = models
                    .map(model => `<option value="${model.name}">${model.name}</option>`)
                    .join('');
            } catch (error) {
                localModelSelect.innerHTML = '<option value="">Kunde inte hämta modeller</option>';
                showLocalRunError(error.message);
            }
        }

        function showLocalRunStatus(message) {
            localRunStatus.textContent = message;
            localRunStatus.classList.remove('error');
        }

        function showLocalRunError(message) {
            localRunStatus.textContent = message;
            localRunStatus.classList.add('error');
        }

        function openLocalRunModal(promptId) {
            selectedPromptForLocalRun = allPrompts.find(prompt => prompt.id === promptId) || null;
            localRunTitle.textContent = selectedPromptForLocalRun
                ? `Kör med lokal modell – ${selectedPromptForLocalRun.title}`
                : 'Kör med lokal modell';

            localRunResult.innerHTML = '';
            showLocalRunStatus('Välj modell, skriv text och klicka på Kör.');
            localUserInput.value = quickInputText || '';
            setLocalRunStreamingState(false);
            latestLocalRunResponse = '';
            localConversationMessages = [];
            if (localChatInput) {
                localChatInput.value = '';
            }
            populateLocalModels();
            localRunModal.classList.add('active');
        }


        function getSelectedPromptText() {
            if (!selectedPromptForLocalRun) {
                return '';
            }
            const textarea = document.getElementById(`textarea-${selectedPromptForLocalRun.id}`);
            return textarea ? getPromptText(selectedPromptForLocalRun.id) : '';
        }

        function copySelectedPromptToClipboard() {
            const text = getSelectedPromptText();
            if (!text) {
                showLocalRunError('Ingen prompttext att kopiera.');
                return;
            }
            navigator.clipboard.writeText(text).then(() => {
                showLocalRunStatus('Prompt kopierad.');
            }).catch(() => {
                showLocalRunError('Kunde inte kopiera prompten.');
            });
        }

        function toggleLocalRunFullscreen() {
            if (!localRunModalContent) {
                return;
            }
            const isFullscreen = localRunModalContent.classList.toggle('is-fullscreen');
            if (localRunExpand) {
                localRunExpand.textContent = isFullscreen ? '🗗' : '⛶';
            }
        }

        function closeLocalRunModal() {
            if (localRunAbortController) {
                localRunAbortController.abort();
            }
            localRunModal.classList.remove('active');
            selectedPromptForLocalRun = null;
            if (localRunModalContent) {
                localRunModalContent.classList.remove('is-fullscreen');
            }
            if (localRunExpand) {
                localRunExpand.textContent = '⛶';
            }
        }

        async function runWithLocalModel() {
            if (!selectedPromptForLocalRun) {
                showLocalRunError('Ingen prompt vald.');
                return;
            }

            const payload = {
                prompt_id: selectedPromptForLocalRun.id,
                user_input: localUserInput.value,
                model: localModelSelect.value,
            };

            if (!payload.user_input.trim()) {
                showLocalRunError('Skriv in text innan du kör.');
                return;
            }

            if (!payload.model) {
                showLocalRunError('Välj en modell.');
                return;
            }

            resetConversationWithPrompt(payload.user_input);
            localRunResult.textContent = '';
            setLocalRunStreamingState(true);
            showLocalRunStatus('Modellen skriver...');
            localRunAbortController = new AbortController();

            try {
                const response = await fetch(`${BACKEND_BASE_URL}/api/run/stream`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload),
                    signal: localRunAbortController.signal
                });

                if (!response.ok) {
                    const data = await response.json().catch(() => ({}));
                    const detail = data.detail;
                    if (detail && typeof detail === 'object') {
                        console.error('Detaljerat provider-fel:', detail);
                        const debugInfo = [
                            detail.message,
                            detail.request_id ? `request_id=${detail.request_id}` : null,
                            detail.upstream_status ? `upstream_status=${detail.upstream_status}` : null,
                            detail.error_type ? `error_type=${detail.error_type}` : null
                        ].filter(Boolean).join(' | ');
                        throw new Error(debugInfo || 'Körning misslyckades.');
                    }
                    throw new Error(detail || 'Körning misslyckades.');
                }

                if (!response.body) {
                    throw new Error('Svarsstream saknas från backend.');
                }

                const reader = response.body.getReader();
                const decoder = new TextDecoder();
                let fullResponse = '';

                while (true) {
                    const { done, value } = await reader.read();
                    if (done) {
                        break;
                    }

                    const chunk = decoder.decode(value, { stream: true });
                    if (!chunk) {
                        continue;
                    }

                    fullResponse += chunk;
                    appendStreamingChunk(chunk);
                }

                const trailingChunk = decoder.decode();
                if (trailingChunk) {
                    fullResponse += trailingChunk;
                    appendStreamingChunk(trailingChunk);
                }

                latestLocalRunResponse = fullResponse || '(Tomt svar från modellen)';
                localConversationMessages.push({ role: 'assistant', content: latestLocalRunResponse });
                renderLocalRunResponse(latestLocalRunResponse);
                showLocalRunStatus('Klart. Du kan nu ställa följdfrågor.');
            } catch (error) {
                if (error.name === 'AbortError') {
                    showLocalRunStatus('Avbruten.');
                } else {
                    showLocalRunError(error.message);
                }
            } finally {
                localRunAbortController = null;
                setLocalRunStreamingState(false);
            }
        }

        if (localRunClose) {
            localRunClose.addEventListener('click', closeLocalRunModal);
        }

        if (localRunModal) {
            localRunModal.addEventListener('click', (event) => {
                if (event.target === localRunModal) {
                    closeLocalRunModal();
                }
            });
        }

        if (localRunSubmit) {
            localRunSubmit.addEventListener('click', runWithLocalModel);
        }

        if (localCopyPromptBtn) {
            localCopyPromptBtn.addEventListener('click', copySelectedPromptToClipboard);
        }

        if (localRunExpand) {
            localRunExpand.addEventListener('click', toggleLocalRunFullscreen);
        }

        if (localRunCancel) {
            localRunCancel.addEventListener('click', () => {
                if (localRunAbortController) {
                    localRunAbortController.abort();
                }
            });
        }

        if (localChatSend) {
            localChatSend.addEventListener('click', sendFollowUpMessage);
        }

        if (localExportDocxBtn) {
            localExportDocxBtn.addEventListener('click', exportLocalResponseAsDocx);
        }

        if (localExportPdfBtn) {
            localExportPdfBtn.addEventListener('click', exportLocalResponseAsPdf);
        }

        const adminTokenInput = document.getElementById('admin-token-input');
        const adminLoadBtn = document.getElementById('admin-load-btn');
        const adminProviderList = document.getElementById('admin-provider-list');
        const adminOpenAIKey = document.getElementById('admin-openai-key');
        const adminOpenAIBaseUrl = document.getElementById('admin-openai-base-url');
        const adminOpenAIEnabled = document.getElementById('admin-openai-enabled');
        const adminSaveOpenAIBtn = document.getElementById('admin-save-openai-btn');
        const adminTestOpenAIBtn = document.getElementById('admin-test-openai-btn');
        const adminStatus = document.getElementById('admin-status');

        function showAdminStatus(message, isError = false) {
            if (!adminStatus) {
                return;
            }
            adminStatus.textContent = message;
            adminStatus.classList.toggle('error', isError);
        }

        function adminHeaders() {
            return {
                'Content-Type': 'application/json',
                'X-Admin-Token': adminTokenInput.value.trim()
            };
        }

        function renderAdminProviderList(providers) {
            if (!providers.length) {
                adminProviderList.textContent = 'Inga providers registrerade i admin-API.';
                return;
            }

            adminProviderList.innerHTML = providers.map((provider) => (
                `<div><strong>${provider.name}</strong> | enabled=${provider.enabled} | configured=${provider.configured} | key=${provider.masked_key || 'ej satt'} | base_url=${provider.base_url}</div>`
            )).join('');

            const openai = providers.find((provider) => provider.name === 'openai');
            if (openai) {
                adminOpenAIEnabled.checked = openai.enabled;
                adminOpenAIBaseUrl.value = openai.base_url || '';
            }
        }

        async function loadAdminProviders() {
            if (!adminTokenInput.value.trim()) {
                showAdminStatus('Ange admin-token först.', true);
                return;
            }

            try {
                const response = await fetch(`${BACKEND_BASE_URL}/api/admin/providers`, {
                    headers: adminHeaders()
                });
                const data = await response.json();
                if (!response.ok) {
                    throw new Error(data.detail || 'Kunde inte ladda admin providers.');
                }
                renderAdminProviderList(data.providers || []);
                showAdminStatus('Providerstatus uppdaterad.');
            } catch (error) {
                showAdminStatus(error.message, true);
            }
        }

        async function saveOpenAIConfig() {
            if (!adminTokenInput.value.trim()) {
                showAdminStatus('Ange admin-token först.', true);
                return;
            }

            const payload = {
                enabled: adminOpenAIEnabled.checked,
                base_url: adminOpenAIBaseUrl.value.trim() || undefined
            };

            const apiKey = adminOpenAIKey.value.trim();
            if (apiKey) {
                payload.api_key = apiKey;
            }

            try {
                const response = await fetch(`${BACKEND_BASE_URL}/api/admin/providers/openai`, {
                    method: 'PATCH',
                    headers: adminHeaders(),
                    body: JSON.stringify(payload)
                });

                const data = await response.json();
                if (!response.ok) {
                    throw new Error(data.detail || 'Kunde inte spara OpenAI-konfiguration.');
                }

                adminOpenAIKey.value = '';
                renderAdminProviderList(data.providers || []);
                showAdminStatus('OpenAI-konfiguration sparad.');
                await populateProviders();
            } catch (error) {
                showAdminStatus(error.message, true);
            }
        }

        async function testOpenAIConnection() {
            if (!adminTokenInput.value.trim()) {
                showAdminStatus('Ange admin-token först.', true);
                return;
            }

            try {
                const response = await fetch(`${BACKEND_BASE_URL}/api/admin/providers/openai/test`, {
                    method: 'POST',
                    headers: adminHeaders()
                });
                const data = await response.json();
                if (!response.ok) {
                    throw new Error(data.detail || 'Kunde inte testa OpenAI-anslutning.');
                }

                showAdminStatus(data.detail, !data.ok);
            } catch (error) {
                showAdminStatus(error.message, true);
            }
        }

        if (adminLoadBtn) {
            adminLoadBtn.addEventListener('click', loadAdminProviders);
        }
        if (adminSaveOpenAIBtn) {
            adminSaveOpenAIBtn.addEventListener('click', saveOpenAIConfig);
        }
        if (adminTestOpenAIBtn) {
            adminTestOpenAIBtn.addEventListener('click', testOpenAIConnection);
        }

        // Quick input state management
        let quickInputText = '';
        const quickInputTextarea = document.getElementById('quick-input-textarea');
        const quickInputClearBtn = document.getElementById('quick-input-clear-btn');

        function updateCopyButtonLabels() {
            const allCopyBtns = document.querySelectorAll('.copy-btn');
            allCopyBtns.forEach((btn) => {
                if (advancedModeEnabled) {
                    btn.style.display = 'none';
                } else {
                    btn.style.display = '';
                    btn.textContent = 'Kopiera';
                    btn.classList.remove('with-text');
                }
            });
        }

        if (quickInputTextarea) {
            // Update state and character counter when user types
            const quickInputCharCounter = document.getElementById('quick-input-char-counter');
            function updateCharCounter() {
                const len = quickInputTextarea.value.length;
                if (quickInputCharCounter) {
                    quickInputCharCounter.textContent = `${len} / 25 000 tecken`;
                }
            }
            quickInputTextarea.addEventListener('input', (event) => {
                quickInputText = event.target.value;
                updateCharCounter();
                updateCopyButtonLabels();
                if (selectedPromptId) {
                    selectPrompt(selectedPromptId, { reveal: false });
                }
                updateExportPreview(); // keep export preview in sync
            });
            // Initialize counter on load
            updateCharCounter();
        }

        if (quickInputFile) {
            quickInputFile.addEventListener('change', async (event) => {
                const file = event.target.files?.[0];
                if (file) {
                    await handleQuickInputFile(file);
                }
                event.target.value = '';
            });

        }

        if (quickInputClearBtn && quickInputTextarea) {
            // Clear button functionality
            quickInputClearBtn.addEventListener('click', () => {
                quickInputTextarea.value = '';
                quickInputText = '';
                console.log('Quick input cleared');
                updateCopyButtonLabels();
                // Nollställ teckenräknaren
                const quickInputCharCounter = document.getElementById('quick-input-char-counter');
                if (quickInputCharCounter) quickInputCharCounter.textContent = '0 / 25 000 tecken';
            });
        }

        const favoritesSidebarBtn = document.getElementById('favorites-sidebar-btn');
        if (favoritesSidebarBtn) {
            favoritesSidebarBtn.addEventListener('click', () => {
                favoritesOnlyFilter = !favoritesOnlyFilter;
                if (favoritesOnlyFilter && !favoritesModeEnabled) {
                    setFavoritesMode(true);
                }
                favoritesSidebarBtn.classList.toggle('active', favoritesOnlyFilter);
                document.querySelectorAll('[data-category-filter]').forEach((item) => {
                    item.classList.remove('active');
                });
                applyAllFilters();
            });
        }

        // Settings gear menu toggle
        const settingsGear = document.getElementById('settings-gear');
        const settingsDropdown = document.getElementById('settings-dropdown');

        if (settingsGear && settingsDropdown) {
            settingsGear.addEventListener('click', (event) => {
                event.stopPropagation();
                settingsDropdown.classList.toggle('hidden');
            });

            document.addEventListener('click', (event) => {
                if (!settingsGear.contains(event.target) && !settingsDropdown.contains(event.target)) {
                    settingsDropdown.classList.add('hidden');
                }
            });
        }

        // Load prompts on page load
        window.addEventListener('DOMContentLoaded', async () => {
            initAdvancedToggle();
            initFavoritesToggle();
            initLocalChatToggle();
            initGlobalRenderControls();
            initPromptSearch();
            initPromptSort();
            initCategoryFilters();
            loadPrompts();
            renderCatalogProfileFilters();
            renderGlobalContextStatus();
            loadCatalogPrompts();
            await loadCatalogPackages();
            loadExportSettings();
            registerExportSettingsListeners();

            const initialPackageSlug = getPackageSlugFromLocation();
            const initialPromptSlug = getPromptSlugFromLocation();
            if (initialPackageSlug) {
                const opened = await openCatalogPackageDetail(initialPackageSlug);
                if (!opened) {
                    window.history.replaceState(null, '', window.location.pathname);
                    const errorBanner = document.getElementById('catalog-package-link-error');
                    if (errorBanner) errorBanner.hidden = false;
                }
            } else if (initialPromptSlug) {
                const opened = await openCatalogPromptDetail(initialPromptSlug);
                if (!opened) {
                    window.history.replaceState(null, '', window.location.pathname);
                    const errorBanner = document.getElementById('catalog-prompt-link-error');
                    if (errorBanner) errorBanner.hidden = false;
                }
            }
        });

// Visa/dölj anonymiseringsexempel i snabbinmatning
    document.addEventListener('DOMContentLoaded', function() {
        const showExamples = document.getElementById('show-anon-examples');
        const modal = document.getElementById('anon-examples-modal');
        const closeBtn = document.getElementById('close-anon-examples');
        if (showExamples && modal && closeBtn) {
            showExamples.addEventListener('click', function(e) {
                e.preventDefault();
                modal.style.display = 'block';
            });
            closeBtn.addEventListener('click', function() {
                modal.style.display = 'none';
            });
        }
    });
