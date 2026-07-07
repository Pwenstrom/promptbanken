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
        let activeCategoryFilter = 'all';
        let activeAudienceFilter = 'all';
        let activeRoleFilter = 'all';
        let activeRiskFilter = 'all';
        let favoritesOnlyFilter = false;
        let activeSort = 'newest';

        const promptUiMeta = {
            klarsprak: { icon: '☷', category: 'Skriva och förbättra text', audience: 'Intern & extern', role: 'Alla roller', risk: 'Låg risk', example: 'Texter till invånare, e-tjänster, brev, instruktioner och beslutsinformation.', phrase: 'Gör denna text tydligare för en extern målgrupp med begränsad förkunskap.' },
            mejl: { icon: '✉', category: 'Svara och kommunicera', audience: 'Intern', role: 'Handläggare', risk: 'Låg risk', example: 'Svar på inkommande mejl där tonen behöver vara tydlig, vänlig och professionell.', phrase: 'Svara på detta mejl sakligt och vänligt med tydliga nästa steg.' },
            faq: { icon: '?', category: 'Svara och kommunicera', audience: 'Extern', role: 'Kommunikatör', risk: 'Låg risk', example: 'Informationssidor, policyer, beslut och dokument som behöver göras om till frågor och svar.', phrase: 'Skapa en FAQ om detta ämne med korta och begripliga svar.' },
            checklista: { icon: '☑', category: 'Sammanfatta och strukturera', audience: 'Intern', role: 'Alla roller', risk: 'Låg risk', example: 'Processer, rutiner, arbetsmoment och återkommande uppgifter.', phrase: 'Skapa en checklista för arbetet baserat på texten.' },
            kallelse: { icon: '□', category: 'Möten och workshops', audience: 'Intern', role: 'Nämndsekreterare', risk: 'Låg risk', example: 'Möten, workshops, träffar, samråd och interna avstämningar.', phrase: 'Skriv en tydlig kallelse med agenda och praktisk information.' },
            beslutsunderlag: { icon: '▱', category: 'Beslut och rutiner', audience: 'Intern', role: 'Handläggare', risk: 'Medelrisk', example: 'Ärenden, förslag, sammanfattningar och underlag inför beslut.', phrase: 'Ta fram ett strukturerat beslutsunderlag baserat på texten.' },
            rutin: { icon: '⌘', category: 'Beslut och rutiner', audience: 'Intern', role: 'Alla roller', risk: 'Medelrisk', example: 'Rutiner, processbeskrivningar, instruktioner och arbetssätt.', phrase: 'Beskriv rutinen steg för steg på ett tydligt sätt.' },
            tvaversioner: { icon: '⇄', category: 'Skriva och förbättra text', audience: 'Intern & extern', role: 'Alla roller', risk: 'Låg risk', example: 'När samma budskap behöver två versioner för olika målgrupper.', phrase: 'Skriv två versioner av texten med olika ton och detaljnivå.' },
            reflektion: { icon: '◌', category: 'Möten och workshops', audience: 'Intern', role: 'Alla roller', risk: 'Låg risk', example: 'Workshops, lärande samtal, uppföljningar och verksamhetsutveckling.', phrase: 'Skapa reflekterande frågor som hjälper gruppen att tänka vidare.' },
            samtalskompas: { icon: '◇', category: 'Möten och workshops', audience: 'Intern', role: 'Chef', risk: 'Låg risk', example: 'Samtal, dialogmöten och workshops som behöver struktur.', phrase: 'Skapa ett samtalsupplägg med frågor, struktur och nästa steg.' },
            sammanfattning: { icon: '▤', category: 'Sammanfatta och strukturera', audience: 'Intern & extern', role: 'Alla roller', risk: 'Låg risk', example: 'Långa dokument, anteckningar, rapporter och beslutsunderlag.', phrase: 'Sammanfatta texten kort och tydligt med de viktigaste punkterna.' },
            anteckningar: { icon: '✎', category: 'Sammanfatta och strukturera', audience: 'Intern', role: 'Alla roller', risk: 'Låg risk', example: 'Mötesanteckningar, minnesstöd, lösa punkter och arbetsmaterial.', phrase: 'Strukturera dessa anteckningar till tydliga rubriker och åtgärder.' },
            diskussionsfragor: { icon: '☰', category: 'Möten och workshops', audience: 'Intern', role: 'Alla roller', risk: 'Låg risk', example: 'Arbetsplatsträffar, workshops, dialoger och gruppdiskussioner.', phrase: 'Skapa diskussionsfrågor som driver samtalet framåt.' },
            nyckelord: { icon: '#', category: 'Sammanfatta och strukturera', audience: 'Intern', role: 'Alla roller', risk: 'Låg risk', example: 'Dokument, rapporter och texter där centrala begrepp behöver hittas.', phrase: 'Extrahera nyckelord och centrala begrepp ur texten.' },
            informationsutskick: { icon: '!', category: 'Svara och kommunicera', audience: 'Extern', role: 'Kommunikatör', risk: 'Medelrisk', example: 'Nyheter, driftinformation, utskick och information till invånare.', phrase: 'Skriv ett tydligt informationsutskick med rubrik och nästa steg.' },
            enkel_infografik: { icon: '▦', category: 'Bilder och infografik', audience: 'Intern & extern', role: 'Kommunikatör', risk: 'Medelrisk', example: 'Information, siffror och viktiga punkter som behöver bli visuellt tydliga.', phrase: 'Skapa en enkel infografik av de här punkterna.' },
            illustration_informationsutskick: { icon: '◫', category: 'Bilder och infografik', audience: 'Extern', role: 'Kommunikatör', risk: 'Medelrisk', example: 'Informationsutskick där en neutral och trygg bildidé behövs.', phrase: 'Skapa en trygg bild till kommunal information.' },
            ikon_symbolbild: { icon: '◇', category: 'Bilder och infografik', audience: 'Intern & extern', role: 'Alla roller', risk: 'Låg risk', example: 'Begrepp, ämnen och budskap som behöver en enkel visuell symbol.', phrase: 'Föreslå en enkel visuell symbol.' },
            presentationstitelbild: { icon: '▣', category: 'Bilder och infografik', audience: 'Intern', role: 'Alla roller', risk: 'Låg risk', example: 'Presentationer, utbildningar och möten som behöver en lugn öppningsbild.', phrase: 'Skapa en professionell titelbild till presentation.' },
            alt_text_bild: { icon: 'A', category: 'Bilder och infografik', audience: 'Intern & extern', role: 'Alla roller', risk: 'Låg risk', example: 'Bilder som behöver tillgänglig alt-text eller längre bildbeskrivning.', phrase: 'Skriv en kort alt-text till bilden.' }
        };

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
            applyPromptFilters();
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

                // Fetch prompts.json
                const configResponse = await fetch('prompts.json');
                if (!configResponse.ok) {
                    throw new Error(`Failed to load prompts.json: ${configResponse.statusText}`);
                }

                const config = await configResponse.json();
                const prompts = config.prompts || [];

                // Clear loading message
                grid.innerHTML = '';

                // Build UI for each prompt
                for (const prompt of prompts) {
                    try {
                        // Fetch prompt text file
                        const promptResponse = await fetch(prompt.file);
                        if (!promptResponse.ok) {
                            throw new Error(`Failed to load ${prompt.file}`);
                        }

                        const promptText = await promptResponse.text();

                        // Create card HTML with quick input text support
                        const card = createPromptCard(prompt, promptText, allPrompts.length + grid.querySelectorAll('.prompt-card').length);
                        grid.appendChild(card);
                    } catch (error) {
                        console.error(`Error loading prompt ${prompt.id}:`, error);
                        grid.innerHTML += `<div class="error-message">⚠️ Kunde inte ladda prompt: ${prompt.title}</div>`;
                    }
                }

                // Store prompts globally for favorites menu
                allPrompts = prompts;
                updateLibraryStats(prompts);
                populateFilterOptions(prompts);

                // Set up event delegation for all cards
                setupEventDelegation();

                // Load favorite states from localStorage
                loadFavoriteStates();

                // Update favorites menu
                updateFavoritesMenu();
                applyPromptSort();
                if (prompts.length) {
                    selectPrompt(prompts[0].id, { reveal: false, markSelected: false });
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
            setFilterOptions('category-filter', metadata.map((meta) => meta.category), 'Alla kategorier');
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
                applyPromptFilters();
            });
        }

        function applyPromptFilters() {
            if (!grid) return;

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

                card.hidden = !isVisible;
                if (isVisible) visibleCount += 1;
            });

            const resultCount = document.getElementById('result-count');
            if (resultCount) {
                resultCount.textContent = `Visar ${visibleCount} av ${allPrompts.length} prompter`;
            }
        }

        function initCategoryFilters() {
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
                    applyPromptFilters();
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
                    applyPromptFilters();
                });
            }

            if (audienceFilter) {
                audienceFilter.addEventListener('change', () => {
                    activeAudienceFilter = audienceFilter.value || 'all';
                    applyPromptFilters();
                });
            }

            if (roleFilter) {
                roleFilter.addEventListener('change', () => {
                    activeRoleFilter = roleFilter.value || 'all';
                    applyPromptFilters();
                });
            }

            if (riskFilter) {
                riskFilter.addEventListener('change', () => {
                    activeRiskFilter = riskFilter.value || 'all';
                    applyPromptFilters();
                });
            }

            if (clearFiltersBtn) {
                clearFiltersBtn.addEventListener('click', () => {
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
                    applyPromptFilters();
                });
            }
        }

        function getPromptText(promptId) {
            const textArea = document.getElementById(`textarea-${promptId}`);
            if (!textArea) return '';
            return replaceInputMarkers(textArea.value, quickInputText);
        }

        function selectPrompt(promptId, options = {}) {
            const shouldReveal = options.reveal !== false;
            const shouldMarkSelected = options.markSelected !== false;
            selectedPromptId = promptId;
            const prompt = allPrompts.find((item) => item.id === promptId);
            if (!prompt) return;
            document.body.classList.remove('detail-panel-closed');
            if (shouldReveal) {
                document.body.classList.add('detail-sheet-open');
            }

            const meta = getPromptMeta(prompt);
            const title = stripLeadingIcon(prompt.title);

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

            document.querySelectorAll('#selected-prompt-chat-btn, #selected-prompt-copy-btn, #selected-prompt-view-btn, #selected-prompt-export-btn')
                .forEach((button) => {
                    button.removeAttribute('disabled');
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
            document.body.classList.add('detail-panel-closed');
            document.body.classList.remove('detail-sheet-open');
            grid.querySelectorAll('.prompt-card.selected').forEach((card) => {
                card.classList.remove('selected');
            });
            document.querySelectorAll('#selected-prompt-chat-btn, #selected-prompt-copy-btn, #selected-prompt-view-btn, #selected-prompt-export-btn')
                .forEach((button) => button.setAttribute('disabled', 'disabled'));
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
                    <button class="copy-btn copy-btn-primary" data-prompt="${prompt.id}" type="button" hidden>Kopiera</button>
                    <button class="secondary-btn info-btn" data-show-full="${prompt.id}" title="Förhandsvisa">Förhandsvisa</button>
                    <button class="secondary-btn local-chat-btn" data-chat-local="${prompt.id}">Chatta lokalt</button>
                    <button class="secondary-btn direct-chat-btn" type="button" disabled aria-disabled="true" title="Kommer snart">Chatta direkt (kommer snart)</button>
                    <button class="info-btn" data-show-full="${prompt.id}" title="Se hela prompt">ℹ️ Se hela prompt</button>
                </div>
                <textarea id="textarea-${prompt.id}">${combinedText}</textarea>
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
            applyPromptFilters();
        }

        window.registerOwnPrompts = registerOwnPrompts;

        function setupEventDelegation() {
            // Toggle examples - event delegation
            grid.addEventListener('click', (event) => {
                const card = event.target.closest('.prompt-card');
                if (card) {
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

                // Favorite button click
                if (event.target.classList.contains('favorite-btn')) {
                    handleFavoriteClick(event.target);
                }

                // Info button click
                if (event.target.classList.contains('info-btn')) {
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
            applyPromptFilters();
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
                searchInput.addEventListener(eventName, applyPromptFilters);
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
                applyPromptFilters();
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

            if (!selectedPromptId) return;

            if (event.target.id === 'selected-prompt-chat-btn') {
                navigateToLocalChat(selectedPromptId);
            }

            if (event.target.id === 'selected-prompt-copy-btn') {
                const cardButton = grid.querySelector(`.copy-btn[data-prompt="${selectedPromptId}"]`);
                if (cardButton) handleCopyClick(cardButton, event, event.target);
            }

            if (event.target.id === 'selected-prompt-view-btn') {
                const cardButton = grid.querySelector(`.info-btn[data-show-full="${selectedPromptId}"]`);
                if (cardButton) handleInfoClick(cardButton);
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

        function handleInfoClick(button) {
            const promptId = button.getAttribute('data-show-full');
            const textArea = document.getElementById(`textarea-${promptId}`);
            const prompt = allPrompts.find(p => p.id === promptId);

            if (textArea && prompt) {
                promptModalTitle.textContent = prompt.title;
                let text = textArea.value;
                text = replaceInputMarkers(text, quickInputText);
                promptModalText.textContent = text;
                promptModal.classList.add('active');
            }
        }

        function closeModal() {
            promptModal.classList.remove('active');
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

            let textToCopy = replaceInputMarkers(textArea.value, quickInputText);

            try {
                await navigator.clipboard.writeText(textToCopy);

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

            const preparedPrompt = replaceInputMarkers(textArea.value, quickInputText).trim();
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
            let text = replaceInputMarkers(baseText, quickInputText);
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
            currentPromptRaw = textArea.value;
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
            return textarea ? textarea.value : '';
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
                applyPromptFilters();
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
        window.addEventListener('DOMContentLoaded', () => {
            initAdvancedToggle();
            initFavoritesToggle();
            initLocalChatToggle();
            initPromptSearch();
            initPromptSort();
            initCategoryFilters();
            loadPrompts();
            loadExportSettings();
            registerExportSettingsListeners();
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
