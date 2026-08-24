// Granskningsvy för creator-inskick.
//
// Alla beslut fattas här av en människa. "Kör granskning" anropar
// edge-funktionen screen-creator-submission, som är rådgivande och saknar
// rättighet att ändra status på något. Inget verdikt aktiverar eller
// blockerar en knapp: ett rött omdöme hindrar inte godkännande, ett grönt
// utlöser ingen publicering.
//
// Se docs/superpowers/specs/2026-08-23-creator-review-flow-design.md.

import { requireSession, requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const VERDICT_LABELS = { gron: 'Grön', gul: 'Gul', rod: 'Röd' };
const TYPE_LABELS = { prompt: 'Prompt', package: 'Paket' };
const SEVERITY_LABELS = { hog: 'hög', medel: 'medel', lag: 'låg' };

const statusElement = document.querySelector('[data-review-status]');
const deniedElement = document.querySelector('[data-review-denied]');
const listElement = document.querySelector('[data-review-list]');
const rowTemplate = document.querySelector('[data-review-row-template]');

function setStatus(message, isError = false) {
  if (!statusElement) return;
  statusElement.textContent = message;
  statusElement.classList.toggle('is-error', isError);
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

// Samma mönster som adminCreatorProfiles.js: RPC:erna vägrar för
// icke-plattformsägare med ett svenskt fel -- visa det som det är.
function handleDenied(error) {
  const message = error?.message || 'Kunde inte genomföra åtgärden.';
  if (/plattformsägare|platform/i.test(message)) {
    if (deniedElement) deniedElement.hidden = false;
  }
  return message;
}

function consentSummary(row) {
  return [
    `Publicering: ${row.consent_shared ? 'ja' : 'nej'}`,
    `Distribution till Open/MCP: ${row.consent_distribution ? 'ja' : 'nej'}`,
    `Rättigheter intygade: ${row.rights_attested ? 'ja' : 'nej'}`
  ].join(' · ');
}

function renderFindings(screening) {
  if (!screening) return '<p class="review-no-screening">Inte granskad än.</p>';
  if (!Array.isArray(screening.findings) || screening.findings.length === 0) {
    return '<p>Inga fynd.</p>';
  }
  const items = screening.findings
    .map((finding) => {
      const severity = SEVERITY_LABELS[finding.allvarlighet] || finding.allvarlighet;
      return `<li><strong>${escapeHtml(finding.kategori)} (${escapeHtml(severity)}):</strong> ${escapeHtml(finding.text)}</li>`;
    })
    .join('');
  return `<ul class="review-findings">${items}</ul>`;
}

function renderSubmissionText(detail) {
  if (detail.subject_type === 'prompt') {
    return `<pre class="mp-template-preview">${escapeHtml(detail.content)}</pre>`;
  }
  const items = Array.isArray(detail.items) ? detail.items : [];
  if (items.length === 0) return '<p>Paketet är tomt.</p>';
  return items
    .map((item, index) =>
      `<h4>${index + 1}. ${escapeHtml(item.title)}</h4>` +
      `<pre class="mp-template-preview">${escapeHtml(item.content)}</pre>`)
    .join('');
}

function renderRow(row) {
  const node = rowTemplate.content.firstElementChild.cloneNode(true);
  const errorElement = node.querySelector('[data-review-error]');
  const detailElement = node.querySelector('[data-review-detail]');
  const verdictElement = node.querySelector('[data-review-verdict]');

  node.dataset.subjectType = row.subject_type;
  node.dataset.subjectId = row.subject_id;

  node.querySelector('[data-review-title]').textContent = row.title;
  verdictElement.textContent = row.latest_verdict
    ? VERDICT_LABELS[row.latest_verdict] || row.latest_verdict
    : 'Ej granskad';
  verdictElement.dataset.verdict = row.latest_verdict || 'none';

  node.querySelector('[data-review-meta]').textContent =
    `${TYPE_LABELS[row.subject_type]} · ${row.creator_display_name || 'Okänd creator'}` +
    (row.item_count ? ` · ${row.item_count} prompts` : '');
  node.querySelector('[data-review-consents]').textContent = consentSummary(row);

  const fail = (message) => {
    errorElement.textContent = message;
    errorElement.hidden = false;
  };

  node.querySelector('[data-review-open]').addEventListener('click', async () => {
    errorElement.hidden = true;
    const { data, error } = await supabase.rpc('get_creator_submission', {
      p_subject_type: row.subject_type,
      p_subject_id: row.subject_id
    });
    if (error) {
      fail(handleDenied(error));
      return;
    }
    const latest = Array.isArray(data.screenings) ? data.screenings[0] : null;
    // Allt som interpoleras här är dubbelt otillförlitligt: prompttexten är
    // skriven av en creator, fynden och återkopplingen av en modell som läst
    // den texten. Varje värde går genom escapeHtml -- rör inte det.
    detailElement.innerHTML =
      renderSubmissionText(data) +
      renderFindings(latest) +
      (latest?.suggested_feedback
        ? `<p class="review-suggestion"><em>Förslag till återkoppling:</em> ${escapeHtml(latest.suggested_feedback)}</p>`
        : '');
    // Sparas så att Begär ändring/Avslå kan förifylla textrutan med
    // AI:ns förslag. Förslaget skickas aldrig automatiskt.
    detailElement.dataset.suggestedFeedback = latest?.suggested_feedback || '';
    detailElement.hidden = false;
  });

  node.querySelector('[data-review-screen]').addEventListener('click', async (event) => {
    errorElement.hidden = true;
    const button = event.currentTarget;
    const originalLabel = button.textContent;
    button.disabled = true;
    button.textContent = 'Granskar...';
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        fail('Sessionen har gått ut. Ladda om sidan.');
        return;
      }
      const response = await fetch(
        `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/screen-creator-submission`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${session.access_token}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            subject_type: row.subject_type,
            subject_id: row.subject_id
          })
        }
      );
      const body = await response.json().catch(() => ({}));
      if (!response.ok) {
        fail(body.error || `Granskningen misslyckades (${response.status}).`);
        return;
      }
      await loadSubmissions();
    } catch (error) {
      fail(`Granskningen kunde inte köras: ${error.message}`);
    } finally {
      button.disabled = false;
      button.textContent = originalLabel;
    }
  });

  node.querySelector('[data-review-approve]').addEventListener('click', async () => {
    errorElement.hidden = true;
    const slug = window.prompt(
      'Adress (slug) i katalogen — små bokstäver och bindestreck:',
      ''
    );
    if (!slug) return;

    const isPrompt = row.subject_type === 'prompt';
    const { error } = await supabase.rpc(
      isPrompt ? 'approve_creator_prompt' : 'approve_creator_package',
      isPrompt
        ? {
            p_content_item_id: row.subject_id,
            p_slug: slug.trim(),
            p_icon_key: 'library',
            p_color_theme: null
          }
        : {
            p_draft_id: row.subject_id,
            p_slug: slug.trim(),
            p_icon_key: 'files',
            p_color_theme: null
          }
    );
    if (error) {
      fail(handleDenied(error));
      return;
    }
    setStatus('Godkänt. Katalogposten ligger som utkast — sätt ikon och bild, publicera sedan.');
    await loadSubmissions();
  });

  const decide = async (rpcName, question) => {
    errorElement.hidden = true;
    const note = window.prompt(question, detailElement.dataset.suggestedFeedback || '');
    if (!note) return;
    const { error } = await supabase.rpc(rpcName, {
      p_subject_type: row.subject_type,
      p_subject_id: row.subject_id,
      p_note: note
    });
    if (error) {
      fail(handleDenied(error));
      return;
    }
    await loadSubmissions();
  };

  node.querySelector('[data-review-changes]').addEventListener('click', () => {
    decide('request_changes_creator_submission', 'Vad ska creatorn ändra?');
  });
  node.querySelector('[data-review-reject]').addEventListener('click', () => {
    decide('reject_creator_submission', 'Varför avslås inskicket?');
  });

  return node;
}

async function loadSubmissions() {
  if (!listElement || !rowTemplate) return;

  setStatus('Laddar inskick...');
  const { data, error } = await supabase.rpc('list_creator_submissions');

  if (error) {
    setStatus(handleDenied(error), true);
    listElement.hidden = true;
    return;
  }

  listElement.innerHTML = '';
  data.forEach((row) => listElement.appendChild(renderRow(row)));
  listElement.hidden = false;
  setStatus(
    data.length
      ? `${data.length} inskick väntar på beslut.`
      : 'Inga inskick väntar på granskning.'
  );
}

async function init() {
  if (!statusElement) return;
  if (!requireSupabaseConfig(statusElement)) return;
  const session = await requireSession();
  if (!session) return;
  await loadSubmissions();
}

document.querySelector('[data-review-refresh]')?.addEventListener('click', () => {
  loadSubmissions().catch((error) => setStatus(error.message || 'Kunde inte ladda inskick.', true));
});

init().catch((error) => setStatus(error.message || 'Kunde inte ladda granskningsvyn.', true));
