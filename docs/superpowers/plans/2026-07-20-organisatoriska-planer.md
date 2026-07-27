# Organisatoriska planer (planer.html/admin.html/login.html) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire personligt Free/Pro på promptbanken.se (flyttar till Valvet), gör Arbetsyta fristående från Pro, och gör alla tre organisatoriska nivåer (Arbetsyta/Förvaltning/Kommun) kontaktbaserade i stället för självköp — utan att röra backend-gating eller ta bort någon markup/kod som kan behöva återaktiveras.

**Architecture:** Rent frontend-arbete i tre statiska sidor + deras JS. `login.html`/`login.js` tappar signup-flödet helt. `planer.html` tappar Free/Pro-korten och blir ren organisationsmarknadsföring. `admin.html`/`admin.js` får en ny gate: workspaces av typen `personal` visar en enkel "inte medlem"-skärm i stället för hela adminpanelen (onboarding-sektionen för personligt bruk blir därmed död kod och tas bort). Synlighetsvalet i "Mina prompts" döljs för vanliga org-medlemmar (hårdkodas till `workspace`). `#uppgradera`-formuläret behåller sin markup och sin `create_pro_order`/`create_shared_workspace`-kod orörd (för att kunna återaktiveras senare) men kopplas om till en kontakt-CTA som inte anropar några RPC:er.

**Tech Stack:** Vanilla JS ES-moduler (`src/*.js`), statisk HTML, `style.css`. Ingen Supabase-schemaändring i den här planen — `ensure_personal_workspace()` anropas fortfarande oförändrat.

**Spec:** `docs/superpowers/specs/2026-07-20-organisatoriska-planer-design.md`

## Global Constraints

- promptbanken.se blir renodlat organisatoriskt (Arbetsyta/Förvaltning/Kommun). Personligt konto, egna mallar, personlig MCP-nyckel och Free/Pro-gränser finns bara i Valvet (valvet.promptbanken.se) härifrån och framåt.
- Ingen datamigrering: inga riktiga användare har personliga Free/Pro-konton på promptbanken.se idag (bekräftat med Peter).
- Arbetsyta blir fristående, inte Pro-beroende: medlemmar läggs till med arbetsyte-ägda MCP-nycklar, inget krav på personligt Pro/Valvet-konto.
- Allt organisatoriskt blir kontaktbaserat. Självköpsflödet (`create_pro_order`/`create_shared_workspace`, prisdata i `planPricing`) rivs INTE — bara `#uppgradera`-formulärets CTA/submit-beteende byts till en kontakt-CTA, så koden kan återaktiveras senare.
- `ensure_personal_workspace()`-RPC:n behålls oförändrad i backend — den anropas fortfarande av `admin.js`s `loadProfile()` när en ny användare saknar profil.
- Svenska i alla användarvänliga texter; samma ton som befintlig copy.
- Inga automattest-ramverk i repot. Statiska textändringar (login.html, planer.html) verifieras med `grep` på filinnehållet. Autentiserade admin.html/admin.js-flöden (personal-gate, visibility-val, uppgradera-CTA) verifieras manuellt i browser mot en riktig Supabase-session, eftersom de beror på inloggad `workspace.type`/roll som inte går att simulera utan riktiga testkonton.
- Rör inte namnet "Delad arbetsyta" (`plan='start'`) i `admin.html`/`admin.js` (dropdown-option, `planNameLabels`, `upgradePlanLabels`) — specen itemiserar bara ett namnbyte till "Arbetsyta" i `planer.html`s marknadsföringstext, inte i den underliggande plankoden. Håll den ändringen där specen faktiskt ber om den.

---

### Task 1: login.html — ta bort signup-flödet

**Files:**
- Modify: `login.html`
- Modify: `src/login.js`
- Modify: `style.css`

**Interfaces:**
- Consumes: inga nya beroenden.
- Produces: inga nya gränssnitt — `data-auth-mode="signup"` och `.auth-plan-compare`/`.auth-plan-col*` finns inte kvar någonstans i repot efter denna task (verifieras med grep i Step 5).

- [x] **Step 1: Ta bort signup-fliken och planjämförelsen i login.html**

I `login.html`, ändra auth-tabs-blocket:

```html
            <div class="auth-tabs" aria-label="Inloggningsläge">
                <button type="button" class="active" data-auth-mode="login">Logga in</button>
                <button type="button" data-auth-mode="signup">Skapa free-konto</button>
                <button type="button" data-auth-mode="reset">Glömt lösenord</button>
            </div>
```

till:

```html
            <div class="auth-tabs" aria-label="Inloggningsläge">
                <button type="button" class="active" data-auth-mode="login">Logga in</button>
                <button type="button" data-auth-mode="reset">Glömt lösenord</button>
            </div>
```

Och ändra blocket efter Google-knappen:

```html
            <p class="auth-legal-links">Genom att fortsätta godkänner du våra <a href="terms.html">användarvillkor</a> och vår <a href="privacy.html">integritetspolicy</a>.</p>

            <div class="auth-plan-compare" aria-label="Planjämförelse">
                <div class="auth-plan-col">
                    <strong>Free</strong>
                    <ul>
                        <li>✓ Hela promptbiblioteket</li>
                        <li>✓ 3 egna mallar</li>
                        <li>✓ 1 MCP-nyckel</li>
                    </ul>
                </div>
                <div class="auth-plan-col auth-plan-col--pro">
                    <strong>Pro</strong>
                    <ul>
                        <li>✓ 100 egna mallar</li>
                        <li>✓ 3 MCP-nycklar</li>
                        <li>✓ Större Valv-gränser</li>
                    </ul>
                </div>
            </div>
            <p class="auth-plan-link"><a href="planer.html">Se alla planer och priser (Arbetsyta, Förvaltning, Kommun)</a></p>
```

till:

```html
            <p class="auth-legal-links">Genom att fortsätta godkänner du våra <a href="terms.html">användarvillkor</a> och vår <a href="privacy.html">integritetspolicy</a>.</p>

            <p class="auth-plan-link">Letar du efter ett personligt konto? Använd <a href="https://valvet.promptbanken.se">Valvet</a> för att spara egna prompts. För organisatorisk åtkomst (Arbetsyta, Förvaltning, Kommun) kontaktar du din administratör eller <a href="mailto:info@promptbanken.se">info@promptbanken.se</a>.</p>
```

- [x] **Step 2: Ta bort signup-grenarna i src/login.js**

Ändra `handleLogin`:

```js
async function handleLogin(event) {
  event.preventDefault();

  if (!requireSupabaseConfig(statusElement)) {
    return;
  }

  setStatus(authMode === 'signup' ? 'Skapar free-konto...' : 'Loggar in...');

  const credentials = {
    email: emailInput.value.trim(),
    password: passwordInput.value
  };

  if (authMode === 'reset') {
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(credentials.email);
    if (resetError) {
      setStatus(resetError.message || 'Kunde inte skicka återställningslänk.', true);
    } else {
      setStatus('Återställningslänk skickad — kolla din e-post.');
    }
    return;
  }

  const { data, error } = authMode === 'signup'
    ? await supabase.auth.signUp(credentials)
    : await supabase.auth.signInWithPassword(credentials);

  if (error) {
    setStatus(error.message || 'Åtgärden misslyckades.', true);
    return;
  }

  if (authMode === 'signup') {
    if (!data.session) {
      setStatus('Kontot är skapat. Bekräfta e-posten och logga sedan in.');
      return;
    }

    const { error: workspaceError } = await supabase.rpc('ensure_personal_workspace');
    if (workspaceError) {
      setStatus(workspaceError.message || 'Kontot skapades men privat workspace kunde inte skapas.', true);
      return;
    }
  }

  window.location.assign(getRedirectTarget());
}
```

till:

```js
async function handleLogin(event) {
  event.preventDefault();

  if (!requireSupabaseConfig(statusElement)) {
    return;
  }

  setStatus('Loggar in...');

  const credentials = {
    email: emailInput.value.trim(),
    password: passwordInput.value
  };

  if (authMode === 'reset') {
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(credentials.email);
    if (resetError) {
      setStatus(resetError.message || 'Kunde inte skicka återställningslänk.', true);
    } else {
      setStatus('Återställningslänk skickad — kolla din e-post.');
    }
    return;
  }

  const { error } = await supabase.auth.signInWithPassword(credentials);

  if (error) {
    setStatus(error.message || 'Åtgärden misslyckades.', true);
    return;
  }

  window.location.assign(getRedirectTarget());
}
```

Ändra `setAuthMode`:

```js
function setAuthMode(nextMode) {
  authMode = nextMode;
  modeButtons.forEach((button) => {
    button.classList.toggle('active', button.dataset.authMode === authMode);
  });
  const passwordField = document.querySelector('[data-password-field]');
  if (authMode === 'reset') {
    submitButton.textContent = 'Skicka återställningslänk';
    passwordInput.required = false;
    if (passwordField) passwordField.hidden = true;
  } else {
    submitButton.textContent = authMode === 'signup' ? 'Skapa free-konto' : 'Logga in';
    passwordInput.required = true;
    if (passwordField) passwordField.hidden = false;
    passwordInput.autocomplete = authMode === 'signup' ? 'new-password' : 'current-password';
  }
  setStatus('');
}
```

till:

```js
function setAuthMode(nextMode) {
  authMode = nextMode;
  modeButtons.forEach((button) => {
    button.classList.toggle('active', button.dataset.authMode === authMode);
  });
  const passwordField = document.querySelector('[data-password-field]');
  if (authMode === 'reset') {
    submitButton.textContent = 'Skicka återställningslänk';
    passwordInput.required = false;
    if (passwordField) passwordField.hidden = true;
  } else {
    submitButton.textContent = 'Logga in';
    passwordInput.required = true;
    if (passwordField) passwordField.hidden = false;
    passwordInput.autocomplete = 'current-password';
  }
  setStatus('');
}
```

- [x] **Step 3: Ta bort den nu oanvända CSS:en för planjämförelsen**

I `style.css`, ta bort hela blocket (kommentar + regler, ca rad 5086-5139):

```css
/* ── Login plan comparison ─────────────────────────────────── */
.auth-plan-compare {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1rem;
    margin-top: 1.75rem;
    padding-top: 1.25rem;
    border-top: 1px solid #e5e7eb;
}

.auth-plan-col {
    padding: 0.75rem 1rem;
    border-radius: 8px;
    background: #f9fafb;
    border: 1px solid #e5e7eb;
}

.auth-plan-col--pro {
    background: #fffbeb;
    border-color: #fcd34d;
}

.auth-plan-col strong {
    display: block;
    font-size: 0.85rem;
    font-weight: 700;
    margin-bottom: 0.5rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: #374151;
}

.auth-plan-col--pro strong {
    color: #92400e;
}

.auth-plan-col ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
}

.auth-plan-col li {
    font-size: 0.8rem;
    color: #6b7280;
}

.auth-plan-col li:first-of-type {
    color: #374151;
}
```

Ta bort blocket helt (även den inledande kommentarraden), men behåll den tomma raden mellan grannblocken (`.auth-legal-links`-relaterad regel ovanför, `.auth-divider` nedanför) så det blir en enda tom rad mellan dem.

- [x] **Step 4: Verifiera lokalt att sidan renderar**

Kör: `npm run web:dev`
Öppna `http://localhost:5173/login.html` (eller den port Vite anger) i browser.
Expected: två flikar syns ("Logga in", "Glömt lösenord") — ingen "Skapa free-konto"-flik. Ingen Free/Pro-jämförelse under Google-knappen. Sista raden hänvisar till Valvet och info@promptbanken.se med fungerande länkar.

- [x] **Step 5: Verifiera att inga rester finns kvar**

```bash
grep -rn "data-auth-mode=\"signup\"\|auth-plan-compare\|auth-plan-col" login.html src/login.js style.css
```
Expected: inga träffar.

- [x] **Step 6: Commit**

```bash
git add login.html src/login.js style.css
git commit -m "feat: remove personal signup flow from login.html"
```

---

### Task 2: planer.html — ta bort Free/Pro, gör Arbetsyta fristående och kontaktbaserad

**Files:**
- Modify: `planer.html`

**Interfaces:**
- Consumes: inga.
- Produces: inga kodgränssnitt — bara marknadsföringstext. Task 5 (admin.js `#uppgradera`-CTA) gör verkligheten bakom `admin.html#uppgradera`-länkarna på den här sidan konsekvent (kontaktbaserat för alla nivåer), men de två taskarna är oberoende av varandra i körordning.

- [x] **Step 1: Uppdatera title/meta och article-lead**

Ändra:

```html
    <title>Planer och priser - Promptbanken</title>
    <meta name="description" content="Promptbankens planer för kommunal verksamhet: Free, Pro, Arbetsyta, Förvaltning och Kommun. Se vad som ingår, vem planen passar och hur du kommer igång.">
```

till:

```html
    <title>Planer och priser - Promptbanken</title>
    <meta name="description" content="Promptbankens organisatoriska planer: Arbetsyta, Förvaltning och Kommun. Se vad som ingår, vem planen passar och hur du kommer igång.">
```

Ändra article-lead-stycket:

```html
                    <p class="article-lead">Promptbanken passar allt från en enskild handläggare som vill testa till en hel kommun som vill styra vilka AI-mallar som används. Hela promptbiblioteket är öppet för alla. Free är gratis och räcker för att komma igång. Betalplanerna ger fler egna mallar, delning i team och nycklar för AI-agenter och integrationer.</p>
```

till:

```html
                    <p class="article-lead">Promptbanken passar allt från ett litet team till en hel kommun som vill styra vilka AI-mallar som används. Hela promptbiblioteket är öppet för alla. De organisatoriska planerna ger delning i team, egna MCP-nycklar och central styrning.</p>
                    <p class="article-lead">Letar du efter ett personligt konto? Använd <a href="https://valvet.promptbanken.se">Valvet</a> för att spara egna prompts.</p>
```

- [x] **Step 2: Rätta den kvarvarande "skapa konto"-texten i topbaren**

Signup-läget försvinner i Task 1 (login.html har ingen "Skapa free-konto"-flik längre). Ändra topbar-länken i `planer.html`:

```html
                <a class="help-btn" href="login.html" id="auth-nav-link"><span class="app-icon" aria-hidden="true" data-icon="user"></span><span id="auth-nav-label">Logga in / skapa konto</span></a>
```

till:

```html
                <a class="help-btn" href="login.html" id="auth-nav-link"><span class="app-icon" aria-hidden="true" data-icon="user"></span><span id="auth-nav-label">Logga in</span></a>
```

(Skriptet längst ner i filen byter redan ut `auth-nav-label`s text till "Min workspace" om användaren har en session — det är oförändrat och rörs inte.)

- [x] **Step 3: Ta bort Free- och Pro-korten, byt namn på "Delad arbetsyta" till "Arbetsyta"**

I `plan-grid`-blocket, ta bort dessa två `<section class="plan-card">`-block helt (Free-kortet och det direkt efterföljande highlight-kortet):

```html
                        <section class="plan-card">
                            <h2>Free</h2>
                            <p class="plan-card-price">0 kr</p>
                            <p class="plan-card-audience">För dig som vill testa</p>
                            <p class="plan-card-value">Kom igång med hela det öppna, kvalitetssäkrade promptbiblioteket.</p>
                            <ul class="plan-card-features">
                                <li>✓ Hela promptbiblioteket</li>
                                <li>✓ 3 egna mallar</li>
                                <li>✓ 1 MCP-nyckel</li>
                                <li>✗ API-nycklar</li>
                                <li>✗ Dela med team</li>
                            </ul>
                            <a class="plan-card-cta secondary-btn" href="login.html">Skapa gratis konto</a>
                        </section>

                        <section class="plan-card plan-card--highlight">
                            <span class="plan-card-badge">Populär</span>
                            <h2>Pro</h2>
                            <p class="plan-card-price" data-price="pro">89 kr/mån</p>
                            <p class="plan-card-audience">För dig som använder AI ofta</p>
                            <p class="plan-card-value">Strukturera, analysera och kvalitetssäkra – med fler egna mallar och nycklar.</p>
                            <ul class="plan-card-features">
                                <li>✓ 100 egna mallar</li>
                                <li>✓ 3 MCP-nycklar</li>
                                <li>✓ Större Valv-gränser</li>
                            </ul>
                            <a class="plan-card-cta primary-btn" href="admin.html#uppgradera">Uppgradera till Pro</a>
                        </section>

```

Det första kortet som blir kvar (direkt efter borttagningen ovan) är dagens "Delad arbetsyta"-kort. Ersätt det:

```html
                        <section class="plan-card">
                            <h2>Delad arbetsyta</h2>
                            <p class="plan-card-price" data-price="team">Pro + 199 kr/mån <small>ägaren betalar ytan</small></p>
                            <p class="plan-card-audience">För ett litet team där alla har Pro</p>
                            <p class="plan-card-value">Dela mallar och arbetssätt i en gemensam yta – ett tillägg till Pro.</p>
                            <ul class="plan-card-features">
                                <li>✓ 200 delade mallar</li>
                                <li>✓ Upp till 5 Pro-användare</li>
                                <li>✓ Nås via medlemmarnas personliga Pro-nycklar</li>
                                <li>✗ Egna arbetsyte-nycklar</li>
                            </ul>
                            <a class="plan-card-cta primary-btn" href="admin.html#uppgradera">Beställ Delad arbetsyta</a>
                        </section>
```

med:

```html
                        <section class="plan-card">
                            <h2>Arbetsyta</h2>
                            <p class="plan-card-price">Pris enligt offert</p>
                            <p class="plan-card-audience">För ett litet team</p>
                            <p class="plan-card-value">Dela mallar och arbetssätt i en gemensam yta – fristående, utan krav på personliga konton.</p>
                            <ul class="plan-card-features">
                                <li>✓ 200 delade mallar</li>
                                <li>✓ Upp till 5 medlemmar</li>
                                <li>✓ Egna arbetsyte-ägda MCP-nycklar</li>
                            </ul>
                            <a class="plan-card-cta secondary-btn" href="admin.html#uppgradera">Kontakta oss</a>
                        </section>
```

Förvaltnings- och Kommun-korten (redan "Pris enligt offert") lämnas oförändrade.

- [x] **Step 4: Uppdatera "Vad är skillnaden"-sektionen**

Ändra rubriken:

```html
                        <h2>Vad är skillnaden mellan Delad arbetsyta, Förvaltning och Kommun?</h2>
```

till:

```html
                        <h2>Vad är skillnaden mellan Arbetsyta, Förvaltning och Kommun?</h2>
```

Ändra första stycket:

```html
                        <p><strong>Delad arbetsyta</strong> är ett tillägg till Pro för en liten arbetsgrupp – till exempel kommunikationsgruppen eller IT-teamet. Alla medlemmar har sin egen Pro och delar en gemensam yta med upp till 5 personer. Ytan har inga egna nycklar; den nås via medlemmarnas personliga Pro-nycklar.</p>
```

till:

```html
                        <p><strong>Arbetsyta</strong> är en fristående nivå för en liten arbetsgrupp – till exempel kommunikationsgruppen eller IT-teamet. Upp till 5 medlemmar delar en gemensam yta med egna arbetsyte-ägda MCP-nycklar. Inget personligt Pro- eller Valvet-konto krävs för medlemmarna.</p>
```

De två andra styckena (Förvaltning, Kommun) lämnas oförändrade.

- [x] **Step 5: Skriv om "Så fungerar köpet"**

Ändra:

```html
                        <p>Pro och Delad arbetsyta beställer du själv direkt i <a href="admin.html#uppgradera">Min workspace</a> – kontot aktiveras direkt och faktura skickas till angiven e-post. Förvaltning och Kommun är en förfrågan: vi återkommer med offert innan avtal tecknas och kontot aktiveras. Ingen betalningsinformation lämnas i tjänsten.</p>
```

till:

```html
                        <p>Alla tre nivåer är en förfrågan: fyll i dina uppgifter under <a href="admin.html#uppgradera">Min workspace</a> eller mejla <a href="mailto:info@promptbanken.se">info@promptbanken.se</a>, så återkommer vi med offert innan avtal tecknas och kontot aktiveras. Ingen betalningsinformation lämnas i tjänsten.</p>
```

- [x] **Step 6: Verifiera i browser**

Kör (om inte redan igång): `npm run web:dev`
Öppna `planer.html`.
Expected: tre kort synliga (Arbetsyta, Förvaltning, Kommun), samtliga "Pris enligt offert". Ingen Free/Pro-kort. Toppstycket hänvisar till Valvet. Topbar-länken visar "Logga in" (inte "skapa konto"). "Så fungerar köpet" nämner ingen direktaktivering.

- [x] **Step 7: Verifiera att inga Free/Pro-rester finns kvar**

```bash
grep -n "Free\|Pro\b\|89 kr\|199 kr\|skapa konto" planer.html
```
Expected: inga träffar (utom möjligt i `mcp.html`-länktext, vilket inte är den här filen).

- [x] **Step 8: Commit**

```bash
git add planer.html
git commit -m "feat: retire Free/Pro cards from planer.html, make Arbetsyta standalone"
```

---

### Task 3: admin.html/admin.js — "inte medlem i arbetsyta"-skärm för personliga workspaces

**Files:**
- Modify: `admin.html`
- Modify: `src/admin.js`

**Interfaces:**
- Consumes: `state.workspace.type` (redan satt av `loadProfile()`/`switchToWorkspace()`), `dashboardElement`/`noProfileElement` (redan deklarerade konstanter i `src/admin.js`).
- Produces: ny funktion `showPersonalNotice()` i `src/admin.js`, nytt element `[data-personal-notice]` i `admin.html`. Ingen annan task i den här planen beror på dessa.

- [x] **Step 1: Lägg till "inte medlem"-skärmen i admin.html**

I `admin.html`, direkt efter den befintliga (redan overksamma) `data-no-profile`-sektionen:

```html
                <section class="workspace-empty" data-no-profile hidden>
                    <h1 id="admin-empty-title">Adminyta</h1>
                    <p>Ditt konto är skapat men inte kopplat till en workspace ännu.</p>
                </section>
```

lägg till direkt efter (före `<section class="admin-dashboard" data-admin-dashboard hidden>`):

```html

                <section class="workspace-empty" data-personal-notice hidden>
                    <h1>Inte medlem i någon arbetsyta</h1>
                    <p>Du är inte medlem i någon organisations-arbetsyta ännu. För eget bruk, använd <a href="https://valvet.promptbanken.se">Valvet</a>. För åtkomst via din kommun/företag, kontakta din administratör eller <a href="mailto:info@promptbanken.se">info@promptbanken.se</a>.</p>
                </section>
```

- [x] **Step 2: Ta bort den personliga onboarding-sektionen (blir dödlig kod efter Step 3-4)**

I `admin.html`, ta bort hela sektionen:

```html
                    <section class="workspace-section admin-onboarding" id="kom-igang-personlig" data-personal-only hidden>
                        <div class="workspace-section-heading">
                            <div>
                                <h2>Välkommen till Promptbanken</h2>
                                <p>Tre saker att börja med.</p>
                            </div>
                        </div>
                        <ol class="onboarding-checklist">
                            <li data-onboarding-step="first-prompt">
                                <span class="onboarding-check" aria-hidden="true">○</span>
                                <div>
                                    <strong>Skapa din första prompt</strong>
                                    <p>Under "Mina prompts" kan du skriva en egen mall, eller kopiera och anpassa en av de öppna standardmallarna.</p>
                                </div>
                            </li>
                            <li data-onboarding-step="mcp-key">
                                <span class="onboarding-check" aria-hidden="true">○</span>
                                <div>
                                    <strong>Skapa en personlig MCP-nyckel</strong>
                                    <p>Under "Integrationer" kan du koppla ditt AI-verktyg (t.ex. Claude eller ChatGPT) direkt till dina mallar.</p>
                                </div>
                            </li>
                            <li data-onboarding-step="explore-pro">
                                <span class="onboarding-check" aria-hidden="true">○</span>
                                <div>
                                    <strong>Utforska promptbiblioteket</strong>
                                    <p>Under "Promptbibliotek" hittar du hela det öppna mallbiblioteket.</p>
                                </div>
                            </li>
                        </ol>
                    </section>

```

(Behåll `<section class="workspace-section admin-onboarding" id="kom-igang" data-org-only hidden>` — den org-sektionen ovanför är oförändrad.)

- [x] **Step 3: Lägg till gaten i loadProfile() och en delad showPersonalNotice()-funktion**

I `src/admin.js`, ändra `loadProfile`:

```js
  state.user = user;
  state.profile = profile;
  state.workspace = workspace;

  setText('[data-user-email]', user.email);
  renderUserAvatar(user);
  setTextWithTitle('[data-workspace-name]', workspace.name);
  setText('[data-workspace-type]', workspaceTypeLabels[workspace.type] || workspace.type);
  setText('[data-workspace-plan]', planNameLabels[workspace.plan] || workspace.plan);
  setText('[data-profile-role]', roleNameLabels[profile.role] || profile.role);
  renderRoleMode(profile.role);
  renderCapabilityState();
  renderPromptFormRules();
  renderPlanInfo();

  dashboardElement.hidden = false;
  noProfileElement.hidden = true;
  setStatus('');
  return true;
}
```

till:

```js
  state.user = user;
  state.profile = profile;
  state.workspace = workspace;

  setText('[data-user-email]', user.email);
  renderUserAvatar(user);

  if (workspace.type === 'personal') {
    showPersonalNotice();
    return false;
  }

  setTextWithTitle('[data-workspace-name]', workspace.name);
  setText('[data-workspace-type]', workspaceTypeLabels[workspace.type] || workspace.type);
  setText('[data-workspace-plan]', planNameLabels[workspace.plan] || workspace.plan);
  setText('[data-profile-role]', roleNameLabels[profile.role] || profile.role);
  renderRoleMode(profile.role);
  renderCapabilityState();
  renderPromptFormRules();
  renderPlanInfo();

  dashboardElement.hidden = false;
  noProfileElement.hidden = true;
  setStatus('');
  return true;
}

function showPersonalNotice() {
  const notice = document.querySelector('[data-personal-notice]');
  if (notice) notice.hidden = false;
  dashboardElement.hidden = true;
  noProfileElement.hidden = true;
  setStatus('');
}
```

`init()` (oförändrad) läser redan returvärdet: `if (hasProfile) { await refreshWorkspaceData(); }` — `false` betyder nu "personligt workspace, visa notisen, hoppa över datainläsning" i stället för sitt tidigare (aldrig nådda) "ingen profil"-syfte.

- [x] **Step 4: Samma gate i switchToWorkspace()**

Ändra:

```js
  state.profile = profile;
  state.workspace = workspace;

  setTextWithTitle('[data-workspace-name]', workspace.name);
  setText('[data-workspace-type]', workspaceTypeLabels[workspace.type] || workspace.type);
  setText('[data-workspace-plan]', planNameLabels[workspace.plan] || workspace.plan);
  setText('[data-profile-role]', roleNameLabels[profile.role] || profile.role);
  renderRoleMode(profile.role);
  renderCapabilityState();
  renderPromptFormRules();
  renderPlanInfo();

  await refreshWorkspaceData();
}
```

till:

```js
  state.profile = profile;
  state.workspace = workspace;

  if (workspace.type === 'personal') {
    showPersonalNotice();
    return;
  }

  const notice = document.querySelector('[data-personal-notice]');
  if (notice) notice.hidden = true;
  dashboardElement.hidden = false;

  setTextWithTitle('[data-workspace-name]', workspace.name);
  setText('[data-workspace-type]', workspaceTypeLabels[workspace.type] || workspace.type);
  setText('[data-workspace-plan]', planNameLabels[workspace.plan] || workspace.plan);
  setText('[data-profile-role]', roleNameLabels[profile.role] || profile.role);
  renderRoleMode(profile.role);
  renderCapabilityState();
  renderPromptFormRules();
  renderPlanInfo();

  await refreshWorkspaceData();
}
```

(De extra raderna som döljer notisen/visar dashboarden igen täcker fallet att en plattformsägare växlar FRÅN en personlig yta tillbaka till en organisationsyta.)

- [x] **Step 5: Ta bort den nu döda renderPersonalOnboarding()**

I `src/admin.js`, ta bort hela funktionen:

```js
function renderPersonalOnboarding() {
  const section = document.getElementById('kom-igang-personlig');
  if (!section || state.workspace?.type !== 'personal') {
    if (section) section.hidden = true;
    return;
  }

  const ownPrompts = state.prompts.filter((item) => (
    (item.owner_user_id === state.user?.id || item.created_by === state.user?.id) && item.status !== 'archived'
  )).length;
  const hasMcpKey = state.mcpKeys.some((key) => !key.revoked_at);

  // Once the user has done at least one of the three things, the banner
  // has served its purpose -- stop showing it so the dashboard doesn't
  // nag a returning user forever.
  if (ownPrompts > 0 || hasMcpKey) {
    section.hidden = true;
    return;
  }

  section.hidden = false;

  const steps = {
    'first-prompt': ownPrompts > 0,
    'mcp-key': hasMcpKey,
    'explore-pro': false
  };

  Object.entries(steps).forEach(([step, done]) => {
    const item = section.querySelector(`[data-onboarding-step="${step}"]`);
    if (!item) return;
    item.classList.toggle('is-done', done);
    const check = item.querySelector('.onboarding-check');
    if (check) check.textContent = done ? '✓' : '○';
  });
}

```

Och ta bort dess enda anropsplats i `refreshWorkspaceData()`:

```js
async function refreshWorkspaceData() {
  setStatus('Uppdaterar...');
  await loadPlanUsage();
  renderPlanInfo();
  renderCapabilityState();
  await Promise.all([loadPrompts(), loadMembers(), loadJoinCodes(), loadMcpKeys(), loadApiKeys(), loadProInvites(), loadProOrders(), loadWorkspaces()]);
  renderOnboardingChecklist();
  renderPersonalOnboarding();
  setStatus('');
}
```

till:

```js
async function refreshWorkspaceData() {
  setStatus('Uppdaterar...');
  await loadPlanUsage();
  renderPlanInfo();
  renderCapabilityState();
  await Promise.all([loadPrompts(), loadMembers(), loadJoinCodes(), loadMcpKeys(), loadApiKeys(), loadProInvites(), loadProOrders(), loadWorkspaces()]);
  renderOnboardingChecklist();
  setStatus('');
}
```

- [x] **Step 6: Verifiera i browser med två testkonton**

Kör: `npm run web:dev`
1. Logga in med ett testkonto vars profil pekar på ett `type='personal'`-workspace (eller skapa ett nytt konto via Google-inloggning utan inbjudan — `ensure_personal_workspace()` skapar automatiskt ett personligt workspace).
   Expected: `admin.html` visar bara rubriken "Inte medlem i någon arbetsyta" med länkar till Valvet och info@promptbanken.se. Ingen av de vanliga adminsektionerna (Översikt, Din plan, Mina prompts osv.) syns.
2. Logga in med ett testkonto som är medlem i ett `type='organization'`-workspace.
   Expected: full adminpanel som tidigare, ingen regression. Under "Din plan" (`#plan`) visas organisationens nivå (Arbetsyta/Förvaltning/Kommun) utan pris eller "Pro"-omnämnande — kontrollera detta specifikt, det är redan så koden fungerar idag (`renderPlanLimitsSummary()`/`renderPlanInfo()`s org-gren nämner varken pris eller "Pro"), så det här är en regressionskontroll snarare än en kodändring. Om kontot är medlem i flera arbetsytor (t.ex. en organisation + en gammal personlig yta): byt till organisationsytan via `data-workspace-switch` — dashboarden ska visas normalt.
3. Som samma flerytes-konto, byt (om möjligt via workspace-switchern) till den personliga ytan.
   Expected: dashboarden döljs igen och "Inte medlem"-skärmen visas.

- [x] **Step 7: Verifiera att inga rester av den gamla sektionen finns kvar**

```bash
grep -n "kom-igang-personlig\|renderPersonalOnboarding\|data-personal-only" admin.html src/admin.js
```
Expected: inga träffar.

- [x] **Step 8: Commit**

```bash
git add admin.html src/admin.js
git commit -m "feat: replace personal workspace dashboard with not-a-member notice"
```

---

### Task 4: admin.html/admin.js — dölj synlighetsvalet för vanliga org-medlemmar

**Files:**
- Modify: `admin.html`
- Modify: `src/admin.js`

**Interfaces:**
- Consumes: `isPlatformOwner()`, `state.workspace.type` (befintliga, oförändrade). Kräver att Task 3 är klar så att den här formulärgrenen bara någonsin nås för `type === 'organization'` (personliga workspaces visar aldrig formuläret).
- Produces: inga nya gränssnitt.

- [x] **Step 1: Markera synlighetsfältet i admin.html**

I `admin.html`, ändra:

```html
                                        <div class="mp-field">
                                            <label>Synlighet
                                                <select name="visibility">
                                                    <option value="workspace">Workspace</option>
                                                    <option value="private">Privat</option>
                                                    <option value="public">Publik efter publicering</option>
                                                </select>
                                            </label>
                                        </div>
```

till:

```html
                                        <div class="mp-field" data-visibility-field>
                                            <label>Synlighet
                                                <select name="visibility">
                                                    <option value="workspace">Workspace</option>
                                                    <option value="private">Privat</option>
                                                    <option value="public">Publik efter publicering</option>
                                                </select>
                                            </label>
                                        </div>
```

- [x] **Step 2: Dölj fältet och hårdkoda värdet för vanliga org-medlemmar i renderPromptFormRules()**

I `src/admin.js`, ändra:

```js
function renderPromptFormRules() {
  if (!visibilitySelect) {
    return;
  }

  visibilitySelect.innerHTML = allowedVisibilityOptions()
    .map(([value, label]) => `<option value="${value}">${label}</option>`)
    .join('');

  if (isPersonalFreeWorkspace()) {
    setText('[data-prompt-limit-note]', 'Free-läge: du kan skapa upp till 3 privata prompts.');
  } else if (state.workspace.type === 'organization') {
    setText('[data-prompt-limit-note]', 'Organisationsläge: prompts sparas för den här organisationen.');
  } else {
    setText('[data-prompt-limit-note]', 'Platform-läge: du kan även skapa publika prompts till Promptbanken.');
  }
}
```

till:

```js
function renderPromptFormRules() {
  if (!visibilitySelect) {
    return;
  }

  const visibilityField = document.querySelector('[data-visibility-field]');
  const hideVisibilityChoice = state.workspace.type === 'organization' && !isPlatformOwner();

  if (hideVisibilityChoice) {
    if (visibilityField) visibilityField.hidden = true;
    visibilitySelect.innerHTML = '<option value="workspace">Workspace</option>';
    visibilitySelect.value = 'workspace';
  } else {
    if (visibilityField) visibilityField.hidden = false;
    visibilitySelect.innerHTML = allowedVisibilityOptions()
      .map(([value, label]) => `<option value="${value}">${label}</option>`)
      .join('');
  }

  if (isPersonalFreeWorkspace()) {
    setText('[data-prompt-limit-note]', 'Free-läge: du kan skapa upp till 3 privata prompts.');
  } else if (state.workspace.type === 'organization') {
    setText('[data-prompt-limit-note]', 'Organisationsläge: prompts sparas för hela organisationen.');
  } else {
    setText('[data-prompt-limit-note]', 'Platform-läge: du kan även skapa publika prompts till Promptbanken.');
  }
}
```

(Texten för organisationsläget ändras från "sparas för den här organisationen" till "sparas för hela organisationen" eftersom valet inte längre finns — prompten delas alltid, det är inte längre en möjlighet bland andra.)

`allowedVisibilityOptions()` rörs inte: den returnerar redan `[['private', ...], ['workspace', ...]]` för org-icke-platform_owner, vilket gör att valideringen i `savePromptUnsafe()` (rad `allowedVisibilityOptions().some(([value]) => value === visibility)`) fortsätter acceptera `'workspace'` utan ändring där.

- [x] **Step 3: Verifiera i browser**

Kör: `npm run web:dev`
1. Logga in som vanlig org-medlem (roll `editor`/`workspace_admin`, inte plattformsägare). Öppna "Mina prompts".
   Expected: inget synlighetsfält syns i skapa-formuläret. Skapa en ny prompt och kontrollera i Supabase (eller i bibliotekslistan efter publicering) att `visibility='workspace'`.
2. Logga in som plattformsägare.
   Expected: synlighetsfältet syns som förut med tre val (Privat/Workspace/Publik).

- [x] **Step 4: Commit**

```bash
git add admin.html src/admin.js
git commit -m "fix: hide visibility choice for org members, default new prompts to workspace"
```

---

### Task 5: admin.js — #uppgradera blir kontaktbaserat för alla nivåer

**Files:**
- Modify: `src/admin.js`

**Interfaces:**
- Consumes: befintlig `upgradeForm`-konstant och `[data-upgrade-form]`/`[data-upgrade-submit]`/`[data-order-mode-badge]`-element i `admin.html` (orörda — markup ska INTE ändras, se Global Constraints).
- Produces: ny funktion `contactForUpgrade(event)`. `reviewUpgradeOrder`/`confirmUpgradeOrder`/`hideUpgradeConfirm`/`planIsSelfService` lämnas kvar i koden oanropade av formuläret (avsiktligt död kod — kan kopplas in igen senare, se Global Constraints) men tas INTE bort.

- [x] **Step 1: Gör knapptext och statusmärke kontaktbaserade i renderUpgradePrice()**

I `src/admin.js`, ändra:

```js
  if (amountEl) amountEl.textContent = pricing?.amount || '—';
  if (noteEl) noteEl.textContent = pricing?.note || '';
  if (submitBtn) {
    submitBtn.textContent = planIsSelfService(plan) ? 'Granska beställning' : 'Skicka förfrågan';
  }

  const selfService = planIsSelfService(plan);
  const badgeEl = document.querySelector('[data-order-mode-badge]');
  if (badgeEl) {
    badgeEl.textContent = selfService ? 'Aktiveras direkt' : 'Förfrågan — ej bindande';
    badgeEl.classList.toggle('is-request', !selfService);
  }
```

till:

```js
  if (amountEl) amountEl.textContent = pricing?.amount || '—';
  if (noteEl) noteEl.textContent = pricing?.note || '';
  if (submitBtn) {
    submitBtn.textContent = 'Kontakta oss om uppgradering';
  }

  const badgeEl = document.querySelector('[data-order-mode-badge]');
  if (badgeEl) {
    badgeEl.textContent = 'Förfrågan — ej bindande';
    badgeEl.classList.add('is-request');
  }
```

- [x] **Step 2: Lägg till contactForUpgrade() direkt efter renderUpgradePrice()**

```js
function contactForUpgrade(event) {
  event.preventDefault();
  setUpgradeStatus('Kontakta oss på info@promptbanken.se för att uppgradera. Ange vilken nivå ni är intresserade av (Arbetsyta, Förvaltning eller Kommun) samt antal medlemmar.');
}
```

- [x] **Step 3: Koppla formuläret till den nya kontakt-CTA:n i stället för reviewUpgradeOrder**

I `src/admin.js`, i `init()`-blocket, ändra:

```js
if (upgradeForm) {
  upgradeForm.addEventListener('submit', reviewUpgradeOrder);
  upgradeForm.querySelector('select[name="plan"]')?.addEventListener('change', syncUpgradeWorkspacesField);
  document.querySelector('[data-upgrade-confirm]')?.addEventListener('click', () => {
    confirmUpgradeOrder().catch((error) => setErrorStatus(error, 'Kunde inte skapa beställningen.', setUpgradeStatus));
  });
  document.querySelector('[data-upgrade-cancel]')?.addEventListener('click', () => {
    hideUpgradeConfirm();
    setUpgradeStatus('Beställningen avbröts.');
  });
  syncUpgradeWorkspacesField();
}
```

till:

```js
if (upgradeForm) {
  upgradeForm.addEventListener('submit', contactForUpgrade);
  upgradeForm.querySelector('select[name="plan"]')?.addEventListener('change', syncUpgradeWorkspacesField);
  syncUpgradeWorkspacesField();
}
```

(`data-upgrade-confirm`/`data-upgrade-cancel`-knapparna och deras panel finns kvar orörda i `admin.html` — de har bara ingen aktiv lyssnare längre, precis som `reviewUpgradeOrder`/`confirmUpgradeOrder`/`hideUpgradeConfirm` finns kvar oanropade i koden.)

- [x] **Step 4: Verifiera i browser**

Kör: `npm run web:dev`
Logga in som org-medlem med admin-roll, gå till `#uppgradera`.
Expected: oavsett vald nivå i dropdownen visar knappen "Kontakta oss om uppgradering" och märket "Förfrågan — ej bindande". Klick på knappen: ingen sida navigeras bort, statusraden visar kontaktmeddelandet, ingen `create_pro_order`/`create_shared_workspace`-anrop sker (inga nätverksanrop till Supabase RPC — kontrollera i devtools Network-fliken).

- [x] **Step 5: Verifiera att self-service-språket är borta ur den aktiva CTA:n**

```bash
grep -n "Granska beställning\|Aktiveras direkt" src/admin.js
```
Expected: inga träffar (dessa strängar fanns bara i `renderUpgradePrice()`, som är ändrad i Step 1).

- [x] **Step 6: Commit**

```bash
git add src/admin.js
git commit -m "feat: make admin.html upgrade CTA contact-based for all plan levels"
```

---

## Utanför scope (från specen, gäller även denna plan)

Statistik för öppen MCP-användning och kontextval/profiler (kommun/skola/företag/privat/generell) är separata, ej påbörjade spår — se `TODO.md` och specens "Utanför scope"-avsnitt. Rör inte dem i den här planen.
