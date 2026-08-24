// Supabase Edge Function: AI-förgranskning av creator-inskick.
//
// Rådgivande, aldrig beslutande. Se
// docs/superpowers/specs/2026-08-23-creator-review-flow-design.md.
//
// SÄKERHETSGRÄNS: funktionen skriver i exakt en tabell,
// creator_submission_screenings. Den har ingen väg att ändra status på
// content_items, creator_package_drafts eller catalog_*. Det är därför en
// kapad modellprompt inte kan publicera eller avslå något. Statusövergångar
// sker uteslutande i RPC:er som kräver en inloggad platform_owner.
//
// Behörighet: get_creator_submission gör platform_owner-kollen åt oss. Vi
// anropar den med anroparens egen JWT, så en obehörig får ett fel därifrån
// innan något OpenAI-anrop hinner ske.

import { createClient } from "npm:@supabase/supabase-js@2";
import { RULES_MARKDOWN, RULES_VERSION } from "./rules.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY")!;

// Modellvalet: uppgiften kräver omdöme om svenska formuleringar, risk och
// rättigheter, men volymen är låg (granskning sker på begäran). Terra är
// mittfältaren. Byt hit gpt-5.6-luna om den räcker, gpt-5.6-sol om den
// inte gör det.
const MODEL = "gpt-5.6-terra";

const SCREENING_SCHEMA = {
  name: "granskningsomdome",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      verdict: { type: "string", enum: ["gron", "gul", "rod"] },
      findings: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            kategori: {
              type: "string",
              enum: ["regelverk", "kvalitet", "risk", "rattigheter", "dublett"],
            },
            allvarlighet: { type: "string", enum: ["hog", "medel", "lag"] },
            text: { type: "string" },
          },
          required: ["kategori", "allvarlighet", "text"],
        },
      },
      suggested_feedback: { type: "string" },
    },
    required: ["verdict", "findings", "suggested_feedback"],
  },
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Saknar Authorization-header." }, 401);
  }

  let subjectType: string;
  let subjectId: string;
  try {
    const body = await req.json();
    subjectType = body.subject_type;
    subjectId = body.subject_id;
  } catch {
    return jsonResponse({ error: "Ogiltig JSON i anropet." }, 400);
  }

  if (subjectType !== "prompt" && subjectType !== "package") {
    return jsonResponse({ error: "Okänd typ. Ange prompt eller package." }, 400);
  }
  if (typeof subjectId !== "string" || subjectId.length === 0) {
    return jsonResponse({ error: "subject_id saknas." }, 400);
  }

  // Klient scopead till anroparens JWT. Används bara för att läsa
  // inskicket via den platform_owner-gatade RPC:n.
  const callerClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData } = await callerClient.auth.getUser(
    authHeader.replace("Bearer ", ""),
  );
  const userId = userData?.user?.id;
  if (!userId) {
    return jsonResponse({ error: "Ogiltig session." }, 401);
  }

  const { data: submission, error: submissionError } = await callerClient.rpc(
    "get_creator_submission",
    { p_subject_type: subjectType, p_subject_id: subjectId },
  );

  if (submissionError) {
    return jsonResponse({ error: submissionError.message }, 403);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // Jämförelselista för dublettbedömning. Vid dagens katalogstorlek (drygt
  // 100 prompts) blir detta ungefär 4 000 tokens. Passerar katalogen ~500
  // poster måste detta bytas mot en kandidatsökning.
  const { data: catalogPrompts } = await admin
    .from("catalog_prompt_variants")
    .select("title, summary, catalog_prompts!inner(slug, status)")
    .eq("context_key", "generell")
    .eq("catalog_prompts.status", "published");

  const comparisonList = (catalogPrompts ?? [])
    .map((row: Record<string, unknown>) => `- ${row.title}: ${row.summary ?? ""}`)
    .join("\n");

  const items = (submission.items ?? []) as Array<Record<string, unknown>>;

  const subjectText = subjectType === "prompt"
    ? `Titel: ${submission.title}\n` +
      `Sammanfattning: ${submission.summary ?? ""}\n\n` +
      `Prompttext:\n${submission.content}`
    : `Pakettitel: ${submission.title}\n` +
      `Sammanfattning: ${submission.summary ?? ""}\n\n` +
      `Ingående prompts i ordning:\n` +
      items
        .map((item, index) => `${index + 1}. ${item.title}\n${item.content}`)
        .join("\n\n");

  const packageInstruction = subjectType === "package"
    ? "\n\nDetta är ett paket. Bedöm helheten utöver de enskilda prompterna: " +
      "hänger de ihop, är ordningen logisk, överlappar de varandra, och " +
      "motsvarar titel och sammanfattning det paketet faktiskt innehåller?"
    : "";

  let openaiResponse: Response;
  try {
    openaiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        response_format: { type: "json_schema", json_schema: SCREENING_SCHEMA },
        messages: [
          {
            role: "system",
            content:
              "Du granskar inskick till Promptbanken mot publiceringsreglerna. " +
              "Du fattar inget beslut — en människa gör det. Skriv fynden och " +
              "förslaget till återkoppling på svenska. Återkopplingen riktas " +
              "direkt till creatorn och ska vara konkret nog att gå att agera på." +
              packageInstruction +
              `\n\n## Publiceringsregler\n\n${RULES_MARKDOWN}`,
          },
          {
            role: "user",
            content:
              `## Befintlig katalog (för dublettbedömning)\n\n${comparisonList}` +
              `\n\n## Inskicket att granska\n\n${subjectText}`,
          },
        ],
      }),
    });
  } catch (error) {
    return jsonResponse(
      { error: `Granskningen kunde inte köras: ${String(error)}` },
      502,
    );
  }

  if (!openaiResponse.ok) {
    const detail = await openaiResponse.text();
    return jsonResponse(
      {
        error:
          `Granskningen kunde inte köras: ${openaiResponse.status} ${detail.slice(0, 300)}`,
      },
      502,
    );
  }

  const payload = await openaiResponse.json();
  const choice = payload.choices?.[0]?.message;

  // Modellen kan vägra svara. Det är inte ett omdöme och ska inte sparas.
  if (choice?.refusal) {
    return jsonResponse(
      { error: `Modellen avböjde att granska inskicket: ${choice.refusal}` },
      502,
    );
  }

  let parsed: { verdict?: string; findings?: unknown; suggested_feedback?: string };
  try {
    parsed = JSON.parse(choice?.content ?? "");
  } catch {
    return jsonResponse(
      {
        error:
          "Modellen svarade i ett format som inte gick att tolka. Ingen granskning sparades.",
      },
      502,
    );
  }

  if (!parsed.verdict) {
    return jsonResponse(
      {
        error:
          "Modellsvaret saknade omdöme. Ingen granskning sparades.",
      },
      502,
    );
  }

  const { data: inserted, error: insertError } = await admin
    .from("creator_submission_screenings")
    .insert({
      subject_type: subjectType,
      subject_id: subjectId,
      verdict: parsed.verdict,
      findings: parsed.findings ?? [],
      suggested_feedback: parsed.suggested_feedback ?? null,
      rules_version: RULES_VERSION,
      model: MODEL,
      created_by: userId,
    })
    .select()
    .single();

  if (insertError) {
    return jsonResponse({ error: insertError.message }, 500);
  }

  return jsonResponse(inserted, 200);
});
