# OpenAI app-directory — submissionshistorik

Arkiv över inskickade versioner av ChatGPT-connectorn, vad som hände med dem
och vad som ändrades efteråt.

| Fil | Version | Utfall | Datum |
| --- | --- | --- | --- |
| [`submission-1.2.1-rejected.json`](submission-1.2.1-rejected.json) | 1.2.1 | `REJECTED` | avslag mottaget 2026-08-22 |
| [`../openai-submission-1.2.2.md`](../openai-submission-1.2.2.md) | 1.2.2 | förbereds | — |

`submission-1.2.1-rejected.json` är den exporterade ansökan som den såg ut när
den avslogs. Två maskningar är gjorda eftersom det här repot är publikt:
signerade `files.openai.com`-URL:er (ikonfiler, innehöll `sig=`-tokens) och
`callback_id`. Allt annat är ordagrant.

---

## Avslaget

OpenAI:s besked, ordagrant:

> After careful review, Promptbanken (v1.2.1) was not approved. Please see the
> details below:
>
> Your privacy policy does not clearly disclose all data uses. Publish a
> complete policy covering data collected, purposes, recipients, retention, and
> user controls, and ensure it reflects current tool inputs and outputs.

En enda invändning. Inget om verktygen, säkerhetsskanningen (`SCANNED_OK`),
tool-annotationerna eller katalogens innehåll.

## Varför policyn föll

Policyn som var publicerad vid inskicket ([version från 2026-08-08][old]) var
skriven för webbtjänsten och beskrev inte connectorn alls. Mot OpenAI:s fem
krav såg det ut så här:

| Krav | Läge i 1.2.1 |
| --- | --- |
| **Data collected** | Delvis. Beskrev besökare, anonym statistik och organisationskonton — men inte vad ett MCP-verktygsanrop skickar in. |
| **Purposes** | Fanns, som en fyra punkters lista. Ingen rättslig grund angavs. |
| **Recipients** | Bara Supabase, och då som lagringsplats snarare än mottagare. GitHub Pages, VPS-leverantören och användarens egen AI-klient nämndes inte. |
| **Retention** | **Saknades helt.** Ingen lagringstid för någon kategori. |
| **User controls** | GDPR-rättigheterna fanns uppräknade. Inget om hur man kopplar bort connectorn. |
| **Reflect current tool inputs and outputs** | **Saknades helt.** De nio verktygen nämndes inte med ett ord. |

Två krav var alltså inte delvis uppfyllda utan helt obesvarade: lagringstider
och verktygens in-/utdata.

### Den faktiska luckan bakom formuleringen

"All data uses" var inte bara en dokumentationsmiss. En behandling av
personuppgifter pågick som varken hade angivet ändamål eller gallringstid:

Caddys accesslogg framför `mcp.promptbanken.se` skrev `remote_ip`,
`remote_port` och `client_ip` på varje anrop, och roterade bara på storlek —
alltså ingen bortre tidsgräns. Policyn nämnde inte att loggen fanns.

Det gick inte att skriva sig ur genom att bara beskriva loggen, eftersom det
som beskrevs då hade varit ogallrad IP-loggning. Åtgärden blev att ändra
beteendet först och beskriva det sedan.

## Vad som gjordes

- **`privacy.html`** — omskriven till version 2.0. Varje datakategori har nu
  ändamål, rättslig grund enligt GDPR art. 6, mottagare och lagringstid. Ett
  eget avsnitt (2.3) går igenom connectorns nio verktyg med exakt vilka
  parametrar som skickas in och vad som returneras.
- **`privacy-en.html`** — engelsk översättning, ny. Granskaren läser engelska.
  `privacy_policy` i 1.2.2 ska peka hit.
- **`deploy/Caddyfile`** i `mcp_promptbanken` — accessloggen strippar numera
  `remote_ip`, `remote_port`, `client_ip` och `Cookie`, utöver `Authorization`
  och `X-MCP-Key` som redan togs bort. `roll_keep_for 720h` ger 30 dagars tak.

## Lärdomar inför nästa inskick

1. **Lagringstid är ett eget krav**, inte en detalj under "lagring". Varje
   kategori behöver en siffra.
2. **Policyn måste beskriva connectorn separat från webbtjänsten.** Granskaren
   bedömer MCP-ytan, inte sajten.
3. **Beskriv inte en behandling du inte vill stå för.** Om loggningen inte
   tål att skrivas ned ska loggningen ändras, inte formuleringen.
4. **Användarens AI-klient är en mottagare** och ska stå med i listan.
5. **Kolla att koden stödjer påståendena.** Policyn utlovar 90 dagars
   kontoradering och 12 månaders inloggningshändelser — inget purge-jobb finns
   för någotdera, till skillnad från `purge_library_usage_events` som sköter
   180-dagarsgallringen av användningsstatistiken. Se punkt 5 i
   [`../openai-submission-1.2.2.md`](../openai-submission-1.2.2.md).

[old]: https://github.com/Pwenstrom/promptbanken/blob/b70cc61/privacy.html
