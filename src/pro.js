import { getCurrentSession, requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const areasContainer = document.getElementById('pro-areas');
const statusBanner = document.getElementById('pro-status-banner');
const authLink = document.getElementById('pro-auth-link');
const authLabel = document.getElementById('pro-auth-label');

const modal = document.getElementById('pro-prompt-modal');
const modalTitle = document.getElementById('pro-modal-title');
const modalText = document.getElementById('pro-modal-text');
const modalCopyButton = document.getElementById('pro-modal-copy');
const modalCloseButton = document.getElementById('pro-modal-close');

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

  card.innerHTML = `
    <div class="card-title-row">
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
    <p class="card-example"><strong>Output:</strong> ${escapeHtml(template.output_format)}</p>
    <div class="actions card-actions">
      ${template.is_unlocked
        ? `<button type="button" class="secondary-btn" data-view-prompt>Visa prompt</button>
           <button type="button" class="primary-btn" data-copy-prompt>Kopiera</button>`
        : `<a class="primary-btn" href="admin.html">Uppgradera till Pro</a>`}
    </div>
  `;

  if (template.is_unlocked) {
    card.querySelector('[data-view-prompt]').addEventListener('click', () => openModal(template));
    card.querySelector('[data-copy-prompt]').addEventListener('click', (event) => copyPrompt(template, event.target));
  }

  return card;
}

function openModal(template) {
  if (!modal || !modalTitle || !modalText) return;
  modalTitle.textContent = template.title;
  modalText.textContent = template.prompt_text;
  modal.classList.add('active');
  modalCopyButton.onclick = () => copyPrompt(template, modalCopyButton);
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
  for (const [, area] of areas) {
    const section = document.createElement('section');
    section.className = 'workspace-section pro-area-section';

    const heading = document.createElement('div');
    heading.className = 'workspace-section-heading';
    heading.innerHTML = `<h2>${escapeHtml(area.label)}</h2>`;
    section.appendChild(heading);

    const grid = document.createElement('div');
    grid.className = 'prompt-grid pro-grid';
    area.items.forEach((template) => grid.appendChild(createCard(template)));
    section.appendChild(grid);

    areasContainer.appendChild(section);
  }
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

if (modalCloseButton) {
  modalCloseButton.addEventListener('click', () => modal.classList.remove('active'));
}
if (modal) {
  modal.addEventListener('click', (event) => {
    if (event.target === modal) modal.classList.remove('active');
  });
}

init().catch((error) => {
  console.error(error);
  if (areasContainer) {
    areasContainer.innerHTML = '<p class="error-message">Ett oväntat fel uppstod.</p>';
  }
});
