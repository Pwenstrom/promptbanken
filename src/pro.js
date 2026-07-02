import { getCurrentSession, requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const areasContainer = document.getElementById('pro-areas');
const statusBanner = document.getElementById('pro-status-banner');
const authLink = document.getElementById('pro-auth-link');
const authLabel = document.getElementById('pro-auth-label');

const detailPanel = document.getElementById('pro-detail-panel');
const detailClose = document.getElementById('pro-detail-close');
const detailTitle = document.getElementById('pro-detail-title');
const detailRisk = document.getElementById('pro-detail-risk');
const detailSyfte = document.getElementById('pro-detail-syfte');
const detailArea = document.getElementById('pro-detail-area');
const detailOutput = document.getElementById('pro-detail-output');
const detailLockedNote = document.getElementById('pro-detail-locked-note');
const detailPreviewSection = document.getElementById('pro-detail-preview-section');
const detailPreview = document.getElementById('pro-detail-prompt-preview');
const detailCopyButton = document.getElementById('pro-detail-copy-btn');
const detailUpgradeButton = document.getElementById('pro-detail-upgrade-btn');

const areaIconMap = {
  kommunikation: 'megaphone',
  forandringsledning: 'route',
  processer: 'workflow',
  beslutsberedning: 'scale',
  visuellt: 'palette',
  ledarskap: 'flag',
  arbetsbank: 'layers'
};

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function setStatusBanner(message, isPro) {
  if (!statusBanner) return;
  statusBanner.textContent = message;
  statusBanner.hidden = false;
  statusBanner.classList.toggle('is-pro', Boolean(isPro));
}

function groupByArea(templates) {
  const areas = new Map();
  for (const template of templates) {
    if (!areas.has(template.area)) {
      areas.set(template.area, { label: template.area_label, items: [] });
    }
    areas.get(template.area).items.push(template);
  }
  return areas;
}

function riskLabel(level) {
  return { low: 'Låg risk', medium: 'Medelrisk', high: 'Hög risk' }[level] || 'Låg risk';
}

function createCard(template) {
  const card = document.createElement('article');
  card.className = 'pro-card prompt-card';
  card.classList.toggle('is-locked', !template.is_unlocked);
  card.dataset.templateId = template.id;

  card.innerHTML = `
    <div class="card-title-row">
      <span class="card-icon app-icon" aria-hidden="true" data-icon="${areaIconMap[template.area] || 'library'}"></span>
      <div>
        <span class="card-kicker">${escapeHtml(template.area_label)}</span>
        <h3>${escapeHtml(template.title)}</h3>
      </div>
      ${!template.is_unlocked ? '<span class="pro-lock-badge" title="Kräver Pro">🔒</span>' : ''}
    </div>
    <p>${escapeHtml(template.syfte)}</p>
    <div class="card-tags">
      <span class="risk-chip" data-risk="${escapeHtml(template.risk_level)}">${riskLabel(template.risk_level)}</span>
    </div>
    <div class="actions card-actions">
      <button type="button" class="select-prompt-btn">Visa</button>
    </div>
  `;

  card.querySelector('.select-prompt-btn').addEventListener('click', (event) => {
    event.stopPropagation();
    selectTemplate(template);
  });
  card.addEventListener('click', () => selectTemplate(template));

  return card;
}

function selectTemplate(template) {
  document.querySelectorAll('.pro-card').forEach((card) => {
    card.classList.toggle('selected', card.dataset.templateId === template.id);
  });

  detailTitle.textContent = template.title;
  detailRisk.textContent = riskLabel(template.risk_level);
  detailSyfte.textContent = template.syfte;
  detailArea.textContent = template.area_label;
  detailOutput.textContent = template.output_format;

  const icon = document.querySelector('#pro-detail-panel .detail-icon');
  if (icon) icon.dataset.icon = areaIconMap[template.area] || 'library';

  if (template.is_unlocked) {
    detailLockedNote.hidden = true;
    detailPreviewSection.hidden = false;
    detailPreview.textContent = template.prompt_text;
    detailCopyButton.hidden = false;
    detailUpgradeButton.hidden = true;
    detailCopyButton.onclick = () => copyPrompt(template, detailCopyButton);
  } else {
    detailLockedNote.hidden = false;
    detailPreviewSection.hidden = true;
    detailCopyButton.hidden = true;
    detailUpgradeButton.hidden = false;
  }

  document.body.classList.add('detail-sheet-open');
  detailPanel.hidden = false;
  detailPanel.focus({ preventScroll: true });
}

async function copyPrompt(template, button) {
  try {
    await navigator.clipboard.writeText(template.prompt_text);
    const original = button.textContent;
    button.textContent = 'Kopierat';
    setTimeout(() => {
      button.textContent = original;
    }, 1800);
  } catch (error) {
    console.error('Kunde inte kopiera prompten.', error);
  }
}

function renderAreas(templates) {
  if (!areasContainer) return;
  areasContainer.innerHTML = '';

  const areas = groupByArea(templates);
  for (const [areaKey, area] of areas) {
    const section = document.createElement('section');
    section.className = 'workspace-section pro-area-section';

    const heading = document.createElement('div');
    heading.className = 'workspace-section-heading';
    heading.innerHTML = `<h2><span class="app-icon" aria-hidden="true" data-icon="${areaIconMap[areaKey] || 'library'}"></span> ${escapeHtml(area.label)}</h2>`;
    section.appendChild(heading);

    const grid = document.createElement('div');
    grid.className = 'prompt-grid pro-grid';
    area.items.forEach((template) => grid.appendChild(createCard(template)));
    section.appendChild(grid);

    areasContainer.appendChild(section);
  }
}

if (detailClose) {
  detailClose.addEventListener('click', () => {
    document.body.classList.remove('detail-sheet-open');
    document.querySelectorAll('.pro-card.selected').forEach((card) => card.classList.remove('selected'));
  });
}

async function init() {
  if (!requireSupabaseConfig()) {
    if (areasContainer) {
      areasContainer.innerHTML = '<p class="error-message">Supabase saknar lokal konfiguration.</p>';
    }
    return;
  }

  const session = await getCurrentSession();
  if (session) {
    authLink.href = 'admin.html';
    authLabel.textContent = 'Min workspace';
  }

  const { data, error } = await supabase.rpc('list_pro_templates');

  if (error) {
    if (areasContainer) {
      areasContainer.innerHTML = `<p class="error-message">Kunde inte ladda Pro-mallar: ${escapeHtml(error.message)}</p>`;
    }
    return;
  }

  const templates = data || [];
  const anyUnlocked = templates.some((t) => t.is_unlocked);

  setStatusBanner(
    anyUnlocked
      ? 'Din plan har Pro aktiverat — alla mallar nedan är upplåsta.'
      : 'Du ser en förhandsvisning av Pro-mallarna. Uppgradera till Pro för att låsa upp hela biblioteket.',
    anyUnlocked
  );

  renderAreas(templates);
}

init().catch((error) => {
  console.error(error);
  if (areasContainer) {
    areasContainer.innerHTML = '<p class="error-message">Ett oväntat fel uppstod.</p>';
  }
});
