const api = window.sephiria;

const elements = {
  sidebar: document.querySelector('#sidebar'),
  content: document.querySelector('#content'),
  capture: document.querySelector('#capture-button'),
  slotCount: document.querySelector('#slot-count'),
  recalibrate: document.querySelector('#recalibrate-button'),
  optimize: document.querySelector('#optimize-button'),
  clearLearning: document.querySelector('#clear-learning-button'),
  alwaysOnTop: document.querySelector('#always-on-top'),
  status: document.querySelector('#status'),
  metrics: document.querySelector('#metrics'),
  emptyState: document.querySelector('#empty-state'),
  results: document.querySelector('#results'),
  recognitionSummary: document.querySelector('#recognition-summary'),
  overflowBadge: document.querySelector('#overflow-badge'),
  currentGrid: document.querySelector('#current-grid'),
  recommendedGrid: document.querySelector('#recommended-grid'),
  calibrationModal: document.querySelector('#calibration-modal'),
  calibrationCanvas: document.querySelector('#calibration-canvas'),
  confirmCalibration: document.querySelector('#confirm-calibration'),
  cancelCalibration: document.querySelector('#cancel-calibration'),
  pickerModal: document.querySelector('#picker-modal'),
  pickerTitle: document.querySelector('#picker-title'),
  capturedPreviewWrap: document.querySelector('#captured-preview-wrap'),
  capturedPreview: document.querySelector('#captured-preview'),
  itemSearch: document.querySelector('#item-search'),
  kindFilter: document.querySelector('#kind-filter'),
  setEmpty: document.querySelector('#set-empty'),
  pickerList: document.querySelector('#picker-list'),
  closePicker: document.querySelector('#close-picker'),
  sourceModal: document.querySelector('#source-modal'),
  sourceList: document.querySelector('#source-list'),
  cancelSource: document.querySelector('#cancel-source')
};

const state = {
  settings: null,
  catalog: [],
  catalogById: new Map(),
  currentCapture: null,
  recognition: null,
  pieces: {},
  unresolved: new Set(),
  optimization: null,
  selectedPosition: null,
  calibrationImage: null,
  calibrationSelection: null,
  calibrationDragStart: null,
  busy: false
};

function setStatus(message, kind = 'normal') {
  elements.status.textContent = message;
  elements.status.classList.toggle('error', kind === 'error');
  elements.status.classList.toggle('working', kind === 'working');
}

function setBusy(value, message = '') {
  state.busy = value;
  elements.capture.disabled = value;
  elements.optimize.disabled = value || !state.recognition;
  if (message) setStatus(message, value ? 'working' : 'normal');
}

function slotLabel(key) {
  const [row, column] = key.split('-').map(Number);
  return `${row + 1}행 ${column + 1}열`;
}

function closeModal(element) {
  element.classList.add('hidden');
}

function showModal(element) {
  element.classList.remove('hidden');
}

async function capture(sourceId = null) {
  if (state.busy) return;
  setBusy(true, '게임 창을 캡처하고 있습니다…');
  closeModal(elements.sourceModal);
  try {
    const response = await api.captureGame(sourceId);
    if (response.requiresSource) {
      renderSourcePicker(response.sources || []);
      setBusy(false, '목록에서 Sephiria 게임 창을 선택하세요.');
      return;
    }

    // Every capture gets a completely fresh recognition result. Only manually
    // confirmed learned samples persist in the main process.
    state.currentCapture = response.imageDataUrl;
    state.recognition = null;
    state.pieces = {};
    state.unresolved = new Set();
    state.optimization = null;
    elements.recalibrate.disabled = false;
    elements.optimize.disabled = true;
    if (!state.settings.calibration) {
      setBusy(false, '처음 한 번만 슬롯 격자 영역을 지정해 주세요.');
      await openCalibration();
      return;
    }
    await recognizeCurrentCapture();
  } catch (error) {
    setBusy(false);
    setStatus(error.message || String(error), 'error');
  }
}

function renderSourcePicker(sources) {
  elements.sourceList.replaceChildren();
  for (const source of sources) {
    const button = document.createElement('button');
    button.className = 'source-card';
    const image = document.createElement('img');
    image.src = source.previewDataUrl;
    image.alt = '';
    const label = document.createElement('span');
    label.textContent = source.name;
    button.append(image, label);
    button.addEventListener('click', () => capture(source.id));
    elements.sourceList.append(button);
  }
  if (sources.length === 0) {
    const message = document.createElement('p');
    message.textContent = '캡처할 수 있는 창이 없습니다. 게임 창의 최소화를 해제해 주세요.';
    elements.sourceList.append(message);
  }
  showModal(elements.sourceModal);
}

async function recognizeCurrentCapture() {
  if (!state.currentCapture || !state.settings.calibration) return;
  setBusy(true, '슬롯과 아이템을 인식하고 있습니다…');
  try {
    const recognition = await api.recognize({
      imageDataUrl: state.currentCapture,
      calibration: state.settings.calibration,
      slotCount: Number(elements.slotCount.value)
    });
    state.recognition = recognition;
    state.pieces = Object.fromEntries(
      Object.entries(recognition.pieces || {}).map(([key, piece]) => [key, { ...piece }])
    );
    state.unresolved = new Set(recognition.unresolved || []);
    state.optimization = null;
    state.settings.slotCount = recognition.slotCount;
    elements.slotCount.value = recognition.slotCount;
    renderCurrentGrid();
    await runOptimization();
    updateRecognitionStatus();
  } catch (error) {
    setStatus(error.message || String(error), 'error');
  } finally {
    setBusy(false);
  }
}

function updateRecognitionStatus() {
  if (!state.recognition) return;
  const recognized = Object.keys(state.pieces).length;
  const unresolved = state.unresolved.size;
  const detected = state.recognition.detectedItemCount || recognized + unresolved;
  elements.recognitionSummary.textContent = unresolved > 0
    ? `아이템 ${recognized}/${detected}개 확정 · 확인 필요 ${unresolved}개`
    : `아이템 ${recognized}개 확정`;
  elements.recognitionSummary.classList.toggle('success', unresolved === 0);
  elements.recognitionSummary.classList.toggle('warning', unresolved > 0);
  setStatus(unresolved > 0
    ? `새 캡처를 인식했습니다. 주황색 ${unresolved}칸만 직접 확인해 주세요.`
    : `새 캡처의 아이템 ${recognized}개를 확인했습니다.`);
  elements.emptyState.classList.add('hidden');
  elements.results.classList.remove('hidden');
  elements.sidebar.scrollTop = 0;
  elements.content.scrollTop = 0;
  elements.content.scrollLeft = 0;
  elements.optimize.disabled = false;
}

function allPositionKeys(slotCount) {
  return Array.from({ length: slotCount }, (_, index) => `${Math.floor(index / 6)}-${index % 6}`);
}

function artifactEvaluationMap(evaluation) {
  return new Map((evaluation?.artifacts || []).map((artifact) => [artifact.key, artifact]));
}

function renderGrid(container, pieces, evaluation, editable) {
  container.replaceChildren();
  const artifactMap = artifactEvaluationMap(evaluation);
  for (const key of allPositionKeys(Number(elements.slotCount.value))) {
    const button = document.createElement('button');
    button.className = 'inventory-cell';
    button.type = 'button';

    const position = document.createElement('span');
    position.className = 'cell-position';
    position.textContent = slotLabel(key);
    button.append(position);

    if (editable && state.unresolved.has(key)) {
      button.classList.add('unresolved');
      const question = document.createElement('span');
      question.className = 'cell-question';
      question.textContent = '확인 필요\n눌러서 선택';
      button.append(question);
    } else {
      const piece = pieces[key];
      const item = piece ? state.catalogById.get(piece.itemId) : null;
      if (item) {
        button.classList.add(item.kind);
        const name = document.createElement('div');
        name.className = 'cell-name';
        name.textContent = item.name;
        button.append(name);
        const value = document.createElement('div');
        value.className = 'cell-value';
        if (item.kind === 'artifact') {
          const artifact = artifactMap.get(key);
          const amplification = artifact?.amplification || 0;
          value.textContent = `증폭 ${amplification} / ${item.capacity}`;
          value.classList.add(amplification > item.capacity ? 'bad' : 'good');
          if (amplification > item.capacity) button.classList.add('overflow');
        } else {
          value.textContent = item.isRotatable ? `회전 ${(piece.rotation || 0) * 90}°` : '석판';
        }
        button.append(value);
      } else {
        const empty = document.createElement('span');
        empty.className = 'cell-empty';
        empty.textContent = '·';
        button.append(empty);
      }
    }

    if (editable) {
      button.title = '클릭: 아이템 선택 / 우클릭: 회전';
      button.addEventListener('click', () => openPicker(key));
      button.addEventListener('contextmenu', async (event) => {
        event.preventDefault();
        const piece = state.pieces[key];
        const item = piece ? state.catalogById.get(piece.itemId) : null;
        if (!item?.isRotatable) return;
        piece.rotation = ((piece.rotation || 0) + 1) % 4;
        state.unresolved.delete(key);
        renderCurrentGrid();
        await runOptimization();
        updateRecognitionStatus();
      });
    } else {
      button.disabled = true;
    }
    container.append(button);
  }
}

function renderCurrentGrid() {
  const currentEvaluation = state.optimization?.before || null;
  renderGrid(elements.currentGrid, state.pieces, currentEvaluation, true);
}

function renderRecommendedGrid() {
  if (!state.optimization) {
    elements.recommendedGrid.replaceChildren();
    return;
  }
  renderGrid(
    elements.recommendedGrid,
    state.optimization.optimized.pieces,
    state.optimization.after,
    false
  );
  const after = state.optimization.after;
  elements.overflowBadge.textContent = after.hasNoOverflow
    ? '증폭 초과 없음'
    : `증폭 초과 ${after.overflowAmount}`;
  elements.overflowBadge.classList.toggle('success', after.hasNoOverflow);
  elements.overflowBadge.classList.toggle('warning', !after.hasNoOverflow);

  elements.metrics.classList.remove('hidden');
  elements.metrics.replaceChildren(
    metricRow('유효 증폭', `${state.optimization.before.totalUsefulAmplification} → ${after.totalUsefulAmplification}`),
    metricRow('한도 정확히 충족', `${state.optimization.before.fullArtifactCount} → ${after.fullArtifactCount}`),
    metricRow('증폭 초과', `${state.optimization.before.overflowAmount} → ${after.overflowAmount}`)
  );
}

function metricRow(label, value) {
  const row = document.createElement('div');
  row.className = 'metric-row';
  const key = document.createElement('span');
  key.textContent = label;
  const output = document.createElement('span');
  output.className = 'metric-value';
  output.textContent = value;
  row.append(key, output);
  return row;
}

async function runOptimization() {
  if (!state.recognition) return;
  elements.optimize.disabled = true;
  setStatus('증폭 초과를 피하는 배치를 계산하고 있습니다…', 'working');
  try {
    state.optimization = await api.optimizeLayout({
      slotCount: Number(elements.slotCount.value),
      pieces: state.pieces
    });
    renderCurrentGrid();
    renderRecommendedGrid();
  } catch (error) {
    setStatus(error.message || String(error), 'error');
  } finally {
    elements.optimize.disabled = false;
  }
}

function openPicker(key) {
  state.selectedPosition = key;
  elements.pickerTitle.textContent = `${slotLabel(key)} 아이템 확인`;
  elements.itemSearch.value = '';
  elements.kindFilter.value = 'all';
  const preview = state.recognition?.cellPreviews?.[key];
  elements.capturedPreviewWrap.classList.toggle('hidden', !preview);
  if (preview) elements.capturedPreview.src = preview;
  renderPickerList();
  showModal(elements.pickerModal);
  elements.itemSearch.focus();
}

function filteredCatalog() {
  const term = elements.itemSearch.value.trim().toLocaleLowerCase();
  const kind = elements.kindFilter.value;
  return state.catalog.filter((item) => {
    if (kind !== 'all' && item.kind !== kind) return false;
    if (!term) return true;
    return item.name.toLocaleLowerCase().includes(term)
      || item.englishName.toLocaleLowerCase().includes(term);
  });
}

function renderPickerList() {
  elements.pickerList.replaceChildren();
  const suggestions = state.recognition?.suggestions?.[state.selectedPosition] || [];
  const suggestionById = new Map(suggestions.map((entry) => [entry.itemId, entry]));
  const shown = new Set();

  if (!elements.itemSearch.value.trim() && elements.kindFilter.value === 'all' && suggestions.length) {
    addPickerHeading('인식 후보');
    for (const suggestion of suggestions.slice(0, 8)) {
      const item = state.catalogById.get(suggestion.itemId);
      if (!item || shown.has(item.id)) continue;
      shown.add(item.id);
      elements.pickerList.append(itemButton(item, suggestion, true));
    }
    addPickerHeading('전체 아이템');
  }

  for (const item of filteredCatalog()) {
    if (shown.has(item.id)) continue;
    elements.pickerList.append(itemButton(item, suggestionById.get(item.id), false));
  }
}

function addPickerHeading(text) {
  const heading = document.createElement('div');
  heading.className = 'picker-section-title';
  heading.textContent = text;
  elements.pickerList.append(heading);
}

function itemButton(item, suggestion, candidate) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'item-row';
  const image = document.createElement('img');
  image.src = item.imageDataUrl;
  image.alt = '';
  const kind = document.createElement('span');
  kind.className = 'item-kind';
  kind.textContent = item.kind === 'artifact' ? `아티팩트 · 한도 ${item.capacity}` : '석판';
  const name = document.createElement('span');
  name.className = 'item-name';
  name.textContent = item.name;
  const badge = document.createElement('span');
  badge.className = 'candidate-badge';
  badge.textContent = candidate ? '인식 후보' : '';
  button.append(image, kind, name, badge);
  button.addEventListener('click', () => chooseItem(item, suggestion));
  return button;
}

async function chooseItem(item, suggestion) {
  const key = state.selectedPosition;
  if (!key) return;
  const existing = state.pieces[key];
  const rotation = item.isRotatable
    ? (suggestion?.rotation ?? (existing?.itemId === item.id ? existing.rotation : 0) ?? 0)
    : 0;
  state.pieces[key] = { itemId: item.id, rotation, confidence: 1, learned: true };
  state.unresolved.delete(key);
  const preview = state.recognition?.cellPreviews?.[key];
  closeModal(elements.pickerModal);
  try {
    if (preview) await api.learnItem({ itemId: item.id, rotation, cellDataUrl: preview });
    renderCurrentGrid();
    await runOptimization();
    updateRecognitionStatus();
  } catch (error) {
    setStatus(`선택은 적용했지만 학습 저장에 실패했습니다: ${error.message || error}`, 'error');
  }
}

async function setSelectedEmpty() {
  const key = state.selectedPosition;
  if (!key) return;
  delete state.pieces[key];
  state.unresolved.delete(key);
  closeModal(elements.pickerModal);
  renderCurrentGrid();
  await runOptimization();
  updateRecognitionStatus();
}

async function openCalibration() {
  if (!state.currentCapture) return;
  state.calibrationSelection = null;
  state.calibrationDragStart = null;
  elements.confirmCalibration.disabled = true;
  state.calibrationImage = new Image();
  await new Promise((resolve, reject) => {
    state.calibrationImage.onload = resolve;
    state.calibrationImage.onerror = reject;
    state.calibrationImage.src = state.currentCapture;
  });
  const canvas = elements.calibrationCanvas;
  canvas.width = state.calibrationImage.naturalWidth;
  canvas.height = state.calibrationImage.naturalHeight;
  drawCalibration();
  showModal(elements.calibrationModal);
}

function canvasPoint(event) {
  const bounds = elements.calibrationCanvas.getBoundingClientRect();
  return {
    x: Math.max(0, Math.min(1, (event.clientX - bounds.left) / bounds.width)),
    y: Math.max(0, Math.min(1, (event.clientY - bounds.top) / bounds.height))
  };
}

function selectionFromPoints(first, second) {
  return {
    x: Math.min(first.x, second.x),
    y: Math.min(first.y, second.y),
    width: Math.abs(first.x - second.x),
    height: Math.abs(first.y - second.y)
  };
}

function drawCalibration() {
  const canvas = elements.calibrationCanvas;
  const context = canvas.getContext('2d');
  context.clearRect(0, 0, canvas.width, canvas.height);
  context.drawImage(state.calibrationImage, 0, 0, canvas.width, canvas.height);
  const rect = state.calibrationSelection;
  if (!rect) return;
  const x = rect.x * canvas.width;
  const y = rect.y * canvas.height;
  const width = rect.width * canvas.width;
  const height = rect.height * canvas.height;
  context.fillStyle = 'rgba(255, 181, 45, .14)';
  context.fillRect(x, y, width, height);
  context.strokeStyle = '#ffbd43';
  context.lineWidth = Math.max(3, canvas.width / 600);
  context.strokeRect(x, y, width, height);
  context.lineWidth = Math.max(1, canvas.width / 1200);
  context.strokeStyle = 'rgba(255,255,255,.80)';
  for (let column = 1; column < 6; column += 1) {
    context.beginPath();
    context.moveTo(x + width * column / 6, y);
    context.lineTo(x + width * column / 6, y + height);
    context.stroke();
  }
  const rows = Math.ceil(Number(elements.slotCount.value) / 6);
  for (let row = 1; row < rows; row += 1) {
    context.beginPath();
    context.moveTo(x, y + height * row / rows);
    context.lineTo(x + width, y + height * row / rows);
    context.stroke();
  }
}

function installEvents() {
  elements.capture.addEventListener('click', () => capture());
  elements.recalibrate.addEventListener('click', () => openCalibration());
  elements.optimize.addEventListener('click', async () => {
    await runOptimization();
    updateRecognitionStatus();
  });
  elements.slotCount.addEventListener('change', async () => {
    const value = await api.setSlotCount(elements.slotCount.value);
    elements.slotCount.value = value;
    state.settings.slotCount = value;
    if (state.currentCapture && state.settings.calibration) await recognizeCurrentCapture();
  });
  elements.alwaysOnTop.addEventListener('change', async () => {
    state.settings.keepOnTop = await api.setAlwaysOnTop(elements.alwaysOnTop.checked);
  });
  elements.clearLearning.addEventListener('click', async () => {
    if (!window.confirm('직접 확인해 저장한 아이템 인식 학습을 모두 지울까요? 다음 캡처에서 다시 확인해야 합니다.')) return;
    await api.clearLearning();
    setStatus('인식 학습을 초기화했습니다. 현재 배치는 유지되며 다음 캡처부터 적용됩니다.');
  });
  elements.cancelSource.addEventListener('click', () => closeModal(elements.sourceModal));
  elements.closePicker.addEventListener('click', () => closeModal(elements.pickerModal));
  elements.setEmpty.addEventListener('click', () => setSelectedEmpty());
  elements.itemSearch.addEventListener('input', renderPickerList);
  elements.kindFilter.addEventListener('change', renderPickerList);
  elements.cancelCalibration.addEventListener('click', () => closeModal(elements.calibrationModal));
  elements.confirmCalibration.addEventListener('click', async () => {
    if (!state.calibrationSelection) return;
    state.settings = await api.saveCalibration(state.calibrationSelection);
    closeModal(elements.calibrationModal);
    await recognizeCurrentCapture();
  });

  elements.calibrationCanvas.addEventListener('pointerdown', (event) => {
    state.calibrationDragStart = canvasPoint(event);
    state.calibrationSelection = { ...state.calibrationDragStart, width: 0, height: 0 };
    elements.calibrationCanvas.setPointerCapture(event.pointerId);
    drawCalibration();
  });
  elements.calibrationCanvas.addEventListener('pointermove', (event) => {
    if (!state.calibrationDragStart) return;
    state.calibrationSelection = selectionFromPoints(state.calibrationDragStart, canvasPoint(event));
    elements.confirmCalibration.disabled = state.calibrationSelection.width < 0.08
      || state.calibrationSelection.height < 0.08;
    drawCalibration();
  });
  elements.calibrationCanvas.addEventListener('pointerup', () => {
    state.calibrationDragStart = null;
  });
  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    closeModal(elements.pickerModal);
    closeModal(elements.sourceModal);
  });
  api.onHotkeyCapture(() => capture());
}

async function initialize() {
  installEvents();
  try {
    const bootstrap = await api.bootstrap();
    state.settings = bootstrap.settings;
    state.catalog = bootstrap.catalog;
    state.catalogById = new Map(state.catalog.map((item) => [item.id, item]));
    elements.slotCount.value = state.settings.slotCount;
    elements.alwaysOnTop.checked = state.settings.keepOnTop;
    setStatus('Sephiria에서 인벤토리를 연 뒤 F8을 누르세요.');
  } catch (error) {
    setStatus(`초기화 실패: ${error.message || error}`, 'error');
  }
}

initialize();
