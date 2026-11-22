const app = document.getElementById('app');
const state = {
  payload: null,
  selectedSlotId: null,
  filter: 'all',
  query: ''
};

const categoryCopy = {
  seed: 'Sow this seed',
  water: 'Use this water',
  fertilizer: 'Apply this fertilizer',
  treatment: 'Apply treatment'
};

function post(endpoint, data = {}) {
  return fetch(`https://${GetParentResourceName()}/${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  }).catch(() => undefined);
}

function selectedSlot() {
  return state.payload?.plot?.slots?.find((slot) => slot.id === state.selectedSlotId) ?? null;
}

function setText(id, value) {
  const element = document.getElementById(id);
  if (element) element.textContent = value ?? '';
}

function open(payload) {
  state.payload = payload;
  state.selectedSlotId = payload?.plot?.slots?.[0]?.id ?? null;
  state.filter = 'all';
  document.querySelectorAll('.filter').forEach((button) => {
    button.classList.toggle('active', button.dataset.filter === 'all');
  });
  const ui = payload.ui || {};
  setText('eyebrow', ui.eyebrow || 'DARK TRAILS COUNTY · PUBLIC AGRICULTURE OFFICE');
  setText('title', ui.title || 'FARMLAND STEWARDSHIP');
  setText('subtitle', ui.subtitle || 'TEND THE SOIL · SHARE THE HARVEST · KEEP THE FRONTIER FED');
  if (ui.backgroundImage) {
    document.querySelector('.masthead').style.setProperty('--background-image', `url("${ui.backgroundImage}")`);
  }
  app.classList.remove('hidden');
  app.setAttribute('aria-hidden', 'false');
  render();
}

function close() {
  app.classList.add('hidden');
  app.setAttribute('aria-hidden', 'true');
  post('close');
}

function metricsFor(slot) {
  if (!slot) return [];
  if (slot.state === 'empty') {
    return [
      ['SOIL', 'Prepared'],
      ['CROP', 'None'],
      ['FURROW', 'Open']
    ];
  }
  const age = Number(slot.ageMinutes || 0);
  const ageLabel = age >= 60
    ? `${Math.floor(age / 60)}h ${age % 60}m`
    : `${age}m`;
  const disease = slot.needsDiagnosis
    ? 'Unknown · farmer only'
    : (slot.diseaseLabel || 'None detected');
  return [
    ['CROP', slot.crop || 'Unknown'],
    ['AGE', ageLabel],
    ['STAGE', slot.stage || 'Growing'],
    ['GROWTH', `${slot.growth ?? 0}%`],
    ['MOISTURE', `${slot.moisture ?? 0}%`],
    ['FERTILITY', `${slot.fertility ?? 0}%`],
    ['HEALTH', slot.health || 'Healthy'],
    ['DISEASE', disease]
  ];
}

function actionFor(supply, slot) {
  if (!slot) return { label: 'SELECT A FURROW', disabled: true };
  if (supply.count <= 0) return { label: 'OUT OF STOCK', disabled: true };
  if (supply.category === 'seed' && slot.state !== 'empty') return { label: 'FURROW OCCUPIED', disabled: true };
  if (supply.category === 'treatment' && slot.state !== 'diseased') return { label: 'NO TREATMENT NEEDED', disabled: true };
  if (supply.category !== 'seed' && slot.state === 'empty') return { label: 'PLANT FIRST', disabled: true };
  if (slot.state === 'ready') return { label: 'READY TO HARVEST', disabled: true };
  return { label: categoryCopy[supply.category] || 'USE SUPPLY', disabled: false };
}

function renderSelected() {
  const slot = selectedSlot();
  setText('selected-name', slot?.label || 'Choose a furrow');
  setText('selected-description', slot
    ? (slot.state === 'empty'
      ? 'This furrow is prepared and ready for seed.'
      : (slot.state === 'diseased'
        ? (slot.needsDiagnosis
          ? `An unidentified crop problem needs diagnosis by a farmer.`
          : `${slot.diseaseLabel || 'A disease'} is affecting this ${slot.crop || 'crop'}.`)
        : `${slot.crop || 'Crop'} is currently ${slot.state}.`))
    : 'Select a field card to view the supplies it can use.');
  const metrics = document.getElementById('metrics');
  metrics.innerHTML = metricsFor(slot).map(([label, value]) => `
    <div class="metric"><span class="metric-label">${label}</span><span class="metric-value">${value}</span></div>
  `).join('');
  setText('action-help', slot
    ? (slot.state === 'ready' ? 'This crop is ready to harvest.' : 'Choose a supply to tend this furrow.')
    : 'Choose a supply from the right to begin.');
  const quickActions = document.getElementById('quick-actions');
  const actions = slot?.state === 'ready'
    ? ['harvest']
    : (slot?.state === 'diseased' ? [slot.needsDiagnosis ? 'diagnose' : 'treatment'] : ['seed', 'water', 'fertilizer']);
  quickActions.innerHTML = actions.map((category) => {
    const disabled = !slot || (category === 'diagnose'
      ? !slot.canDiagnose
      : (category === 'harvest'
      ? slot.state !== 'ready'
      : (category === 'treatment' ? slot.state !== 'diseased' : (category === 'seed' ? slot.state !== 'empty' : slot.state === 'empty' || slot.state === 'ready'))));
    const label = category === 'diagnose' && !slot?.canDiagnose ? 'FARMER REQUIRED' : category.toUpperCase();
    return `<button class="quick-action" type="button" data-category="${category}" ${disabled ? 'disabled' : ''}>${label}</button>`;
  }).join('');
  quickActions.querySelectorAll('[data-category]').forEach((button) => {
    button.addEventListener('click', () => {
      if (button.dataset.category === 'harvest' || button.dataset.category === 'diagnose') {
        post('farmAction', { action: button.dataset.category, plotId: state.payload.plot.id, slotId: slot.id });
        return;
      }
      state.filter = button.dataset.category;
      document.querySelectorAll('.filter').forEach((candidate) => candidate.classList.toggle('active', candidate.dataset.filter === state.filter));
      renderSupplies();
      document.getElementById('provision-panel').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    });
  });
}

function renderSlots() {
  const allSlots = state.payload?.plot?.slots || [];
  const layout = state.payload?.plot?.layout || {};
  const requestedColumns = Number(layout.columns);
  const columns = Number.isFinite(requestedColumns) ? Math.min(Math.max(Math.floor(requestedColumns), 1), 6) : null;
  const rows = Number.isFinite(Number(layout.rows)) ? Math.max(Math.floor(Number(layout.rows)), 1) : null;
  const dimensions = state.payload?.plot?.dimensions || {};
  setText('plot-label', state.payload?.plot?.label || 'Public Field');
  setText('plot-layout', rows && columns ? `${rows} × ${columns}` : 'FLEXIBLE');
  setText('plot-capacity', `${allSlots.length} / ${rows && columns ? rows * columns : allSlots.length}`);
  setText('plot-access', state.payload?.plot?.access || 'PUBLIC');
  const normalisedQuery = state.query.trim().toLowerCase();
  const slots = normalisedQuery
    ? allSlots.filter((slot) => `${slot.label || ''} ${slot.crop || ''} ${slot.state || ''}`.toLowerCase().includes(normalisedQuery))
    : allSlots;
  setText('field-count', `${slots.length} SHOWN · ${rows && columns ? `${rows} × ${columns}` : 'FLEXIBLE'} LAYOUT`);
  const slotList = document.getElementById('slot-list');
  if (columns) {
    slotList.style.setProperty('--furrow-columns', `repeat(${columns}, minmax(0, 1fr))`);
  } else {
    slotList.style.removeProperty('--furrow-columns');
  }
  slotList.innerHTML = slots.length ? slots.map((slot) => `
    <button type="button" class="slot-card ${slot.state || ''} ${slot.id === state.selectedSlotId ? 'selected' : ''}" data-slot-id="${slot.id}">
      <span class="card-top"><span class="slot-number">FURROW ${slot.number || '—'}</span><span class="slot-state">${slot.state || 'ready'}</span></span>
      <h3>${slot.label || 'Unnamed Furrow'}</h3>
      <span class="slot-status">${slot.state === 'empty' ? 'Prepared soil · ready for seed' : (slot.state === 'diseased' ? (slot.needsDiagnosis ? 'Farmer diagnosis required' : (slot.diseaseLabel || 'Treatment required')) : `${slot.growth ?? 0}% growth · ${slot.moisture ?? 0}% moisture`)}</span>
      <div class="progress-track"><div class="progress-fill" style="width: ${slot.growth || 0}%"></div></div>
    </button>
  `).join('') : '<div class="empty-state">No furrows match that search.</div>';
  slotList.querySelectorAll('[data-slot-id]').forEach((button) => {
    button.addEventListener('click', () => {
      state.selectedSlotId = button.dataset.slotId;
      render();
    });
  });
}

function renderSupplies() {
  const currentSlot = selectedSlot();
  const provisionPanel = document.getElementById('provision-panel');
  const provisionTitle = document.getElementById('provision-title');
  provisionPanel.hidden = state.filter === 'all';
  provisionTitle.textContent = state.filter === 'all' ? 'Choose a supply' : `Choose ${state.filter === 'seed' ? 'a seed' : state.filter}`;
  if (state.filter === 'all') return;
  const supplies = (state.payload?.supplies || []).filter((supply) => state.filter === 'all' || supply.category === state.filter);
  const supplyList = document.getElementById('supply-list');
  if (!supplies.length) {
    supplyList.innerHTML = '<div class="empty-state">No supplies are configured for this category.</div>';
    return;
  }
  supplyList.innerHTML = supplies.map((supply) => {
    const action = actionFor(supply, currentSlot);
    return `
      <article class="supply-card">
        <div class="card-top"><span class="supply-icon">${supply.icon || supply.category[0]?.toUpperCase() || '•'}</span><span class="supply-count">${supply.count ?? 0} IN SATCHEL</span></div>
        <h3>${supply.label}</h3>
        <p>${supply.description || 'No field notes provided.'}</p>
        <button class="supply-action" data-supply-id="${supply.id}" type="button" ${action.disabled ? 'disabled' : ''}>${action.label}</button>
      </article>
    `;
  }).join('');
  document.querySelectorAll('[data-supply-id]').forEach((button) => {
    button.addEventListener('click', () => {
      const supply = state.payload.supplies.find((candidate) => candidate.id === button.dataset.supplyId);
      const slot = selectedSlot();
      const action = actionFor(supply, slot);
      if (action.disabled || !slot) return;
      post('farmAction', {
        action: supply.category,
        plotId: state.payload.plot.id,
        slotId: slot.id,
        supplyId: supply.id
      });
    });
  });
}

function render() {
  if (!state.payload) return;
  renderSelected();
  renderSlots();
  renderSupplies();
}

document.getElementById('close-button').addEventListener('click', close);
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !app.classList.contains('hidden')) close();
});
document.querySelectorAll('.filter').forEach((button) => {
  button.addEventListener('click', () => {
    state.filter = button.dataset.filter;
    document.querySelectorAll('.filter').forEach((candidate) => candidate.classList.toggle('active', candidate === button));
    renderSupplies();
  });
});

document.getElementById('furrow-search').addEventListener('input', (event) => {
  state.query = event.target.value;
  renderSlots();
});

window.addEventListener('message', (event) => {
  const { action, payload } = event.data || {};
  if (action === 'open' || action === 'update') open(payload);
  if (action === 'close') close();
});

// Local browser preview only. RedM never adds ?preview=1, so live NUI traffic
// continues to be supplied exclusively by the client script.
if (new URLSearchParams(window.location.search).has('preview')) {
  open({
    ui: { eyebrow: 'PUBLIC FARMING', title: 'FARMLAND' },
    plot: {
      id: 'preview-plot',
      label: 'Valentine Field',
      access: 'PUBLIC',
      layout: { rows: 3, columns: 4 },
      slots: [
        { id: '01', number: '01', state: 'growing', label: 'Young Corn', crop: 'Corn', ageMinutes: 28, stage: 'young', growth: 44, moisture: 68, fertility: 20, health: 'Healthy' },
        { id: '02', number: '02', state: 'growing', label: 'Young Wheat', crop: 'Wheat', ageMinutes: 34, stage: 'young', growth: 52, moisture: 74, fertility: 35, health: 'Healthy' },
        { id: '03', number: '03', state: 'thirsty', label: 'Thirsty Corn', crop: 'Corn', ageMinutes: 18, stage: 'sprout', growth: 23, moisture: 12, fertility: 10, health: 'Thirsty' },
        { id: '04', number: '04', state: 'diseased', label: 'Unidentified Crop Problem', crop: 'Wheat', ageMinutes: 41, stage: 'young', growth: 59, moisture: 61, fertility: 25, health: 'Afflicted', needsDiagnosis: true, canDiagnose: false },
        { id: '05', number: '05', state: 'ready', label: 'Mature Corn', crop: 'Corn', ageMinutes: 96, stage: 'mature', growth: 100, moisture: 57, fertility: 45, health: 'Healthy' },
        { id: '06', number: '06', state: 'growing', label: 'Young Corn', crop: 'Corn', ageMinutes: 36, stage: 'young', growth: 55, moisture: 42, fertility: 30, health: 'Healthy' },
        { id: '07', number: '07', state: 'empty', label: 'Empty Soil', growth: 0, moisture: 0, fertility: 0, health: 'Prepared' },
        { id: '08', number: '08', state: 'growing', label: 'Young Wheat', crop: 'Wheat', ageMinutes: 27, stage: 'young', growth: 38, moisture: 76, fertility: 15, health: 'Healthy' },
        { id: '09', number: '09', state: 'diseased', label: 'Powdery Mildew Wheat', crop: 'Wheat', ageMinutes: 58, stage: 'young', growth: 70, moisture: 85, fertility: 40, health: 'Afflicted', diseaseLabel: 'Powdery Mildew', canDiagnose: true },
        { id: '10', number: '10', state: 'growing', label: 'Sprouting Corn', crop: 'Corn', ageMinutes: 12, stage: 'sprout', growth: 15, moisture: 82, fertility: 15, health: 'Healthy' },
        { id: '11', number: '11', state: 'empty', label: 'Empty Soil', growth: 0, moisture: 0, fertility: 0, health: 'Prepared' },
        { id: '12', number: '12', state: 'ready', label: 'Mature Wheat', crop: 'Wheat', ageMinutes: 83, stage: 'mature', growth: 100, moisture: 63, fertility: 55, health: 'Healthy' }
      ]
    },
    supplies: [
      { id: 'corn', category: 'seed', label: 'Corn Seed', count: 12, icon: 'C' },
      { id: 'water_bucket', category: 'water', label: 'Water Bucket', count: 3, icon: 'W' },
      { id: 'compost', category: 'fertilizer', label: 'Compost', count: 5, icon: 'F' },
      { id: 'copper_fungicide', category: 'treatment', label: 'Copper Fungicide', count: 2, icon: 'T' }
    ]
  });
}
