# Granskningsflöde, promptformulär och rollinfo — Design

## Bakgrund

Peter rapporterade efter att ha börjat testa admin-läget: skapa prompt och
granskningsflödet känns för tunt, och rollväljaren i "Bjud in kollega"
förklarar inte vad rollerna faktiskt innebär.

Nuvarande beteende (bekräftat i koden, inte antaget):
- `content_items.status` har fyra värden (`draft`/`review`/`published`/`archived`)
  men ingenting i UI:t sätter någonsin `review` — en admin klickar
  "Publicera" direkt från ett `draft`, utan att se prompttexten först.
- Granskningslistan (`[data-review-prompts]` på Översikt,
  `src/admin.js:688-705`) visar bara titel/kategori/målgrupp/datum — aldrig
  själva innehållet.
- "Skapa prompt"-formulären (både per-arbetsyta "Snabb prompt" och
  huvudformuläret i "Mina prompts") har bara Titel + Prompttext +
  Synlighet. Kolumnen `content_items.summary` finns redan i databasen men
  fylls aldrig i från UI.
- "Bjud in kollega"-formuläret i arbetsyte-kortet (`renderWorkspaces`,
  `src/admin.js:1303-1322`) har en rollväljare (Redigerare/Läsare/
  Administratör) utan förklaring. En annan, separat inbjudningsform
  (`inviteMemberForm`, Team/organisation-fliken) har redan en live
  rollbeskrivning kopplad till `roleLabels`-dicten
  (`src/admin.js:4-10`, wiring `src/admin.js:2389-2398`) — samma mönster
  saknas bara i arbetsyte-kortets formulär.

## Mål

1. Ett riktigt granskningssteg: redaktören skickar aktivt in en prompt för
   granskning, granskaren ser hela innehållet innan hen beslutar, och kan
   antingen godkänna+publicera eller skicka tillbaka med en kommentar.
2. "Skapa prompt"-formulären får ett kort beskrivningsfält.
3. "Bjud in kollega"-formuläret i arbetsyte-kortet förklarar rollerna live,
   på samma sätt som redan görs i Team/organisation-fliken.

Inget av detta ändrar existerande behörighetsmodell (viewer < editor <
workspace_admin < workspace_owner < platform_owner) — alla nya knappar
återanvänder befintlig `isAdminRole()`-gating där admin-rättigheter redan
krävs idag (t.ex. för "Publicera").

## Del 1 — Granskningsflöde

### Databasändring

Ny migration `supabase/migrations/20260711100000_review_note.sql`:

```sql
alter table public.content_items
    add column if not exists review_note text;
```

Ingen RLS-ändring behövs — kolumnen omfattas av samma rader/policyer som
resten av `content_items`. Peter kör migrationen själv i SQL Editor, som
vanligt för det här projektet.

### Statusövergångar

```
draft --[redaktör: "Skicka för granskning"]--> review
review --[admin: "Godkänn & publicera"]--> published
review --[admin: "Skicka tillbaka"]--> draft (review_note sätts)
```

`published → draft` (Avpublicera) och `→ archived` (Ta bort) är oförändrade
befintliga flöden och rörs inte.

### UI — redaktörens vy ("Mina prompts", `renderPrompts()`, `src/admin.js:645-668`)

Ny knapp bredvid befintliga Redigera/Ta bort, bara när `item.status ===
'draft'` och användaren äger prompten:

```html
<button type="button" data-submit-review-prompt="${item.id}">Skicka för granskning</button>
```

Om `item.status === 'review'`: dölj Redigera-knappen helt (kan inte
redigeras medan den ligger i kö — undviker att admin granskar en version
som redan hunnit ändras). Statuspillen som redan visas för varje kort
(`src/admin.js:651`, `statusLabels.review = 'Granskning'`) räcker som
statusindikator — ingen ny pill behövs.

Om `item.review_note` finns och `item.status === 'draft'` (dvs. den kom
tillbaka från granskning): visa en liten varningsrad ovanför kortet:

```html
<p class="mp-hint is-error">Skickades tillbaka: ${escapeHtml(item.review_note)}</p>
```

`review_note` nollställs (sätts till `null`) nästa gång redaktören klickar
"Skicka för granskning" igen, så gamla kommentarer inte hänger kvar efter
en ny granskningsrunda.

### UI — granskarens vy (granskningslistan, `src/admin.js:688-705`)

Varje rad får:
- En **"Visa"/"Dölj"**-knapp som togglar en expanderad `<div class="mp-template-preview">`
  med hela `item.content` (samma escaping/mönster som redan används för
  "Mina prompts"-förhandsvisningen, `src/admin.js:667`).
- **"Godkänn & publicera"** — sätter `status: 'published'`, `published_at: now()`
  (samma fält `publishPrompt()` redan sätter, `src/admin.js:2043-2051`).
- **"Skicka tillbaka"** — öppnar ett `prompt()`-dialogfönster för valfri
  kommentar. Tomt/avbrutet fält → sparar standardtexten
  `"Behöver justeras innan publicering."` istället för tomt värde. Sätter
  `status: 'draft'`, `review_note: <kommentaren>`.

Båda knapparna kräver `isAdminRole(state.profile.role)`, exakt samma gate
som befintliga "Publicera"-knappen redan använder.

Endast prompts med `status === 'review'` visas i granskningslistan
framöver (idag är filtret `status !== 'published'`, vilket alltså också
inkluderade rena drafts ingen bett om granskning — ändras till
`status === 'review'`, eftersom en admin annars skulle se och kunna
godkänna/publicera opublicerade utkast ingen någonsin skickat in).

### Nya funktioner i `src/admin.js`

```js
async function submitPromptForReview(promptId) {
  const { error } = await supabase
    .from('content_items')
    .update({ status: 'review', review_note: null })
    .eq('id', promptId);

  if (error) {
    setErrorStatus(error, 'Kunde inte skicka prompten för granskning.');
    return;
  }

  setStatus('Prompten skickades för granskning.');
  await loadPrompts();
}

async function sendPromptBackToDraft(promptId) {
  const note = window.prompt('Kommentar till redaktören (valfritt):') || '';
  const reviewNote = note.trim() || 'Behöver justeras innan publicering.';

  const { error } = await supabase
    .from('content_items')
    .update({ status: 'draft', review_note: reviewNote })
    .eq('id', promptId);

  if (error) {
    setErrorStatus(error, 'Kunde inte skicka tillbaka prompten.');
    return;
  }

  setStatus('Prompten skickades tillbaka till utkast.');
  await loadPrompts();
}
```

Click-delegation: samma mönster som befintliga `[data-publish-prompt]`
m.fl. i den delegerade lyssnaren (`src/admin.js` runt rad 2542-2570) —
lägg `submitReviewButton`/`sendBackButton`-par bredvid.

`loadPrompts()`s `select(...)`-kolumnlista (`src/admin.js:1369`) utökas
med `review_note`.

## Del 2 — Kort beskrivning i skapa-prompt-formulären

Huvudformuläret i "Mina prompts" (`data-prompt-form`, `admin.html:405-437`)
har redan ett "Kort beskrivning"-fält som sparas korrekt
(`src/admin.js:1932`, `1860`) — inget att ändra där. Det är bara
arbetsyte-kortets "Snabb prompt"-formulär (`data-quick-create-form`,
`src/admin.js:1284-1301`) som saknar det. Nytt fält mellan Titel och
Synlighet i det formuläret:

```html
<label>Kort beskrivning
  <input name="summary" maxlength="140" placeholder="En rad om vad prompten gör">
</label>
```

Valfritt fält, ingen `required`. `submitQuickCreatePrompt()`
(`src/admin.js:1327-1364`) läser `formData.get('summary')?.toString().trim()
|| null` och skickar med i `insert()`-anropet som `summary`.

Listvisningen (`src/admin.js:649`) använder redan
`item.summary || item.category || 'Ingen sammanfattning.'` — ingen ändring
behövs där, den fylls bara i äntligen.

## Del 3 — Rollinfo på arbetsyte-kortets bjud-in-formulär

`renderWorkspaces()` (`src/admin.js:1303-1322`): lägg ett
`data-invite-role-hint`-attribut med unikt workspace-id-suffix (flera kort
kan vara öppna/renderas om, så hint-elementet måste vara
workspace-scopat — matchar `data-workspace-invite-form data-workspace-id`
redan på formuläret):

```html
<label>Roll
  <select name="role" data-invite-role-select>
    <option value="editor">Redigerare</option>
    <option value="viewer">Läsare</option>
    <option value="workspace_admin">Administratör</option>
  </select>
</label>
<p class="mp-hint" data-invite-role-hint>${escapeHtml(roleLabels.editor)}</p>
```

(Förifylld med `roleLabels.editor` eftersom `editor` är förvalt värde i
`<select>`.)

Efter `renderWorkspaces()` byggt om DOM:en, koppla en `change`-lyssnare per
formulär (i samma delegerade click/change-listener-block som redan
hanterar övriga dynamiska formulär, eller en riktad
`querySelectorAll('[data-invite-role-select]')`-loop som körs sist i
`renderWorkspaces()`):

```js
list.querySelectorAll('[data-invite-role-select]').forEach((select) => {
  const hint = select.closest('form')?.querySelector('[data-invite-role-hint]');
  if (!hint) return;
  select.addEventListener('change', () => {
    hint.textContent = roleLabels[select.value] || '';
  });
});
```

Ingen ändring av `roleLabels`-dicten (`src/admin.js:4-10`) — texten
återanvänds som den redan är.

## Testning / verifiering

Inga automatiska tester i det här projektet (per `CLAUDE.md`). Verifiering:
- `node --input-type=module --check` + `npm run build` för syntax/bygge.
- Manuell temp-disable-teknik (kommentera bort admin.js-scripttaggen, ta
  bort `hidden` på `.admin-dashboard`, mocka `state`) för att verifiera
  DOM/CSS-rendering av de nya knapparna/fälten utan inloggning.
- Full click-through (skicka för granskning → godkänn/skicka tillbaka →
  se kommentar) kräver en riktig inloggad session — flaggas för Peter att
  testa manuellt, samma mönster som tidigare launch-check-uppgifter i det
  här projektet.

## Avgränsning (medvetet utanför scope)

- Ingen ny roll eller behörighetsnivå införs.
- Ingen historik/logg över tidigare granskningsrundor — bara senaste
  `review_note` sparas, skrivs över vid varje ny granskningsrunda.
- Ingen e-postavisering när nåt skickas för granskning eller skickas
  tillbaka — bara UI-status.
- Kategori-fält och förhandsgranskning-vid-spara i skapa-prompt-formuläret
  övervägdes men valdes bort av Peter (bara "Kort beskrivning" läggs till).
