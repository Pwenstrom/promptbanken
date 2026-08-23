# OpenAI-submission 1.2.2 — fält att uppdatera

Avslag på 1.2.1: *"Your privacy policy does not clearly disclose all data uses.
Publish a complete policy covering data collected, purposes, recipients,
retention, and user controls, and ensure it reflects current tool inputs and
outputs."*

## 1. Branding

| Fält | Nytt värde |
| --- | --- |
| `privacy_policy` | `https://app.promptbanken.se/privacy-en.html` |
| `terms_of_service` | `https://app.promptbanken.se/terms.html` (oförändrad) |
| `customer_support` | `https://app.promptbanken.se/support.html` (oförändrad) |
| `contact_email` | fyll i — var `null` i 1.2.1 |

Den engelska policyn är den granskaren ska läsa. Svenska versionen ligger kvar
på `/privacy.html` och de länkar till varandra.

## 2. Test cases — riktiga id:n

1.2.1 skickades med platshållarna `<selected template ID>` och
`<selected package ID>`. Granskaren kör prompten ordagrant. Ersätt med:

**Test case 2 — `get_template`**

> Show me the full template with ID `1221debc-650d-42f2-8680-c901353c3c6c`.

Motsvarar mallen *Driftstörningsinformation* (area `kommunikation`,
risk `medium`) — samma mall som test case 1 hittar via `search_templates`,
så de två fallen hänger ihop.

**Test case 4 — `list_package_prompts`**

> List the prompts in the package `kommunikation`.

Obs: `list_package_prompts` och `get_package` tar `package_slug`, inte ett
UUID. Beskrivningen i test-caset ska säga "package slug", inte "package ID".

Verifierade slugs i prod: `anti-slop`, `arbetsbank`, `beslutsberedning`,
`forandringsledning`, `hall-traden`, `kommunikation`, `ledarskap`, `processer`,
`sag-emot-mig`, `skarpare-funktionskrav`, `skola-undervisning-larare`,
`supportarenden`, `vardagspaket`, `visuellt`, `workshop-och-facilitering`.

Test case 1, 3 och 5 fungerar som de är.

## 3. Övrigt som var tomt i 1.2.1

- `screenshots` — `null`. Lägg upp minst en bild av katalogen.
- `categories` — `null`.
- `brand_color` / `brand_color_dark` — `null`.
- `physical_address` — `null`. `entity_type` är `individual`, så adress
  saknas helt.

Inget av detta nämndes i avslaget, men de är tomma fält som kan bli nästa
invändning.

## 4. Release notes 1.2.2 (förslag)

```
1.2.2 — Privacy policy update

Rewrites the privacy policy to state, for every category of data:
what is collected, why, on what legal basis, who receives it, how long
it is kept, and what controls the user has.

- Documents the connector's actual tool inputs and outputs per tool
- Access logs no longer record client IP addresses, and rotate after
  30 days
- Usage statistics are non-identifying and deleted after 180 days
- Recipients listed: Supabase (EU), Swedish VPS host, GitHub Pages
- English translation published at /privacy-en.html

No change to the nine public read-only tools or their behaviour.
```

## 5. Kvarstående åtaganden utan teknisk motsvarighet

Policyn utlovar två saker som i dag hanteras manuellt, inte av kod:

- radering av konto och innehåll inom 90 dagar
- inloggningshändelser sparas högst 12 månader

Det finns inget purge-jobb för dessa, till skillnad från
`purge_library_usage_events` som sköter 180-dagarsgallringen av statistiken.
Bygg motsvarande jobb eller håll rutinen dokumenterad.
