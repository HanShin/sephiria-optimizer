const fs = require('node:fs');
const path = require('node:path');
const {
  bufferFromDataUrl,
  cellImages,
  decodePng,
  descriptor,
  descriptorDistance,
  detectSlotCount,
  detectedKind,
  normalizeCell,
  normalizeTemplate,
  raster,
  resizeNearest,
  rotateQuarterTurns,
  rowCount,
  shapeDistance,
  toDataUrl
} = require('./image');

class Recognizer {
  constructor(catalog, resourceDirectory, userDataDirectory) {
    this.catalog = catalog;
    this.catalogById = new Map(catalog.map((item) => [item.id, item]));
    this.templateDirectory = path.join(resourceDirectory, 'templates');
    this.learnedFile = path.join(userDataDirectory, 'learned.json');
    this.templates = [];
    this.prepared = false;
    this.builtIn = this.loadBuiltIn(resourceDirectory);
    this.learned = this.loadLearned();
  }

  loadBuiltIn(resourceDirectory) {
    try {
      const samples = JSON.parse(fs.readFileSync(path.join(resourceDirectory, 'screen-samples.json'), 'utf8'));
      return Array.isArray(samples) ? samples.filter((sample) => this.catalogById.has(sample.itemId)) : [];
    } catch {
      return [];
    }
  }

  loadLearned() {
    try {
      const parsed = JSON.parse(fs.readFileSync(this.learnedFile, 'utf8'));
      return Array.isArray(parsed) ? parsed.filter((sample) => this.catalogById.has(sample.itemId)) : [];
    } catch {
      return [];
    }
  }

  saveLearned() {
    fs.mkdirSync(path.dirname(this.learnedFile), { recursive: true });
    const temporary = `${this.learnedFile}.tmp`;
    fs.writeFileSync(temporary, JSON.stringify(this.learned));
    fs.renameSync(temporary, this.learnedFile);
  }

  prepare(progress = () => {}) {
    if (this.prepared) return;
    this.templates = [];
    this.catalog.forEach((item, itemIndex) => {
      const file = path.join(this.templateDirectory, `${item.templateKey}.png`);
      if (!fs.existsSync(file)) return;
      const source = decodePng(fs.readFileSync(file));
      const rotations = item.kind === 'tablet' && item.isRotatable ? [0, 1, 2, 3] : [0];
      for (const rotation of rotations) {
        const normalized = normalizeTemplate(rotateQuarterTurns(source, rotation));
        if (!normalized) continue;
        this.templates.push({
          itemId: item.id,
          kind: item.kind,
          rotation,
          descriptor: descriptor(normalized),
          raster: raster(rotateQuarterTurns(source, rotation), 40, true),
          learned: false
        });
      }
      progress(itemIndex + 1, this.catalog.length);
    });
    this.prepared = true;
  }

  learnedTemplatesFor(kind) {
    return [...this.builtIn, ...this.learned]
      .filter((sample) => this.catalogById.get(sample.itemId)?.kind === kind).map((sample) => ({
      ...sample,
      kind,
      descriptor: Uint8Array.from(sample.descriptor),
      learned: true
    }));
  }

  topMatches(cell, limit = 24) {
    this.prepare();
    const kind = detectedKind(cell);
    if (!kind) return [];
    // Normalize the slot to a fixed size first. Otherwise small rounding changes
    // in connected components can substantially change a learned descriptor when
    // Windows display scaling switches between 100%, 125%, and 200%.
    const normalized = normalizeCell(resizeNearest(cell, 96, 96), kind);
    if (!normalized) return [];
    const target = descriptor(normalized);
    const targetRaster = raster(cell, 40, false);
    const candidates = [...this.templates.filter((template) => template.kind === kind), ...this.learnedTemplatesFor(kind)];
    const bestByItemAndRotation = new Map();
    for (const template of candidates) {
      const descriptorScore = descriptorDistance(target, template.descriptor);
      const shapeScore = !template.learned && kind === 'artifact'
        ? shapeDistance(template.raster, targetRaster)
        : null;
      const rawDistance = shapeScore ?? descriptorScore;
      const distance = template.learned && rawDistance > 8 ? 100 : rawDistance;
      const key = `${template.itemId}#${template.rotation}`;
      const current = bestByItemAndRotation.get(key);
      if (!current || distance < current.distance) {
        bestByItemAndRotation.set(key, {
          ...template,
          distance,
          descriptorScore,
          shapeScore,
          rankDistance: distance
        });
      }
    }

    const entries = [...bestByItemAndRotation.values()];
    if (kind === 'artifact') {
      const generic = entries.filter((entry) => !entry.learned);
      [...generic].sort((left, right) => left.shapeScore - right.shapeScore)
        .forEach((entry, index) => { entry.shapeRank = index; });
      [...generic].sort((left, right) => left.descriptorScore - right.descriptorScore)
        .forEach((entry, index) => { entry.descriptorRank = index; });
      for (const entry of generic) {
        // Rank fusion keeps both outline/color matches and normalized-icon matches
        // near the top. It replaces the macOS-only Vision feature print reranking.
        entry.rankDistance = Math.min(entry.shapeRank, entry.descriptorRank)
          + (entry.shapeRank + entry.descriptorRank) / 1000;
      }
    }
    for (const entry of entries.filter((candidate) => candidate.learned)) {
      // A genuinely close user-confirmed screen sample always outranks generic
      // artwork; a stale sample remains behind everything via the distance-8 gate.
      entry.rankDistance = entry.distance <= 8 ? -1 + entry.distance / 100 : 10_000 + entry.distance;
    }
    const sorted = entries.sort((left, right) => left.rankDistance - right.rankDistance);
    const secondDistance = sorted[1]?.rankDistance ?? sorted[0]?.rankDistance ?? 1;
    return sorted.slice(0, Math.max(1, limit)).map((entry, index) => ({
      itemId: entry.itemId,
      rotation: entry.rotation,
      distance: entry.distance,
      confidence: index === 0
        ? entry.learned && entry.distance <= 8
          ? 1
          : Math.max(0, Math.min(1, Math.max(0, secondDistance - entry.rankDistance) / Math.max(Math.abs(secondDistance), 0.001) * 5))
        : 0,
      learned: entry.learned,
      signalAgreement: kind !== 'artifact' || entry.learned
        || (entry.shapeRank <= 2 && entry.descriptorRank <= 2)
    }));
  }

  recognize(imageDataUrl, inventoryRect, requestedSlotCount) {
    const image = decodePng(bufferFromDataUrl(imageDataUrl));
    const clampedRequested = Math.min(60, Math.max(18, Number(requestedSlotCount) || 34));
    const detected = detectSlotCount(image, inventoryRect);
    let slotCount = clampedRequested;
    if (detected) {
      slotCount = rowCount(detected) === rowCount(clampedRequested) ? Math.max(clampedRequested, detected) : detected;
    }
    const cells = cellImages(image, inventoryRect, slotCount);
    const pieces = {};
    const unresolved = [];
    const suggestions = {};
    const cellPreviews = {};
    let detectedItemCount = 0;

    for (const [key, cell] of cells) {
      const matches = this.topMatches(cell, 24);
      if (matches.length === 0) continue;
      detectedItemCount += 1;
      cellPreviews[key] = toDataUrl(cell);
      const unique = [];
      const seen = new Set();
      for (const match of matches) {
        if (seen.has(match.itemId)) continue;
        seen.add(match.itemId);
        unique.push(match);
      }
      suggestions[key] = unique;
      const best = matches[0];
      const acceptedLearned = best.learned && best.distance <= 8 && best.confidence >= 0.45;
      // Cross-platform generic artwork comparison is useful for presenting a
      // short candidate list, but is not safe enough to auto-confirm. Automatic
      // confirmation is reserved for an actual, previously verified screen sample.
      const acceptedGeneric = false;
      if (acceptedLearned || acceptedGeneric) {
        pieces[key] = { itemId: best.itemId, rotation: best.rotation, confidence: best.confidence, learned: best.learned };
      } else {
        unresolved.push(key);
      }
    }
    return { slotCount, pieces, unresolved, suggestions, cellPreviews, detectedItemCount };
  }

  learn(itemId, rotation, cellDataUrl) {
    const item = this.catalogById.get(itemId);
    if (!item) throw new Error('선택한 아이템을 찾지 못했습니다.');
    const cell = decodePng(bufferFromDataUrl(cellDataUrl));
    const normalized = normalizeCell(resizeNearest(cell, 96, 96), item.kind);
    if (!normalized) throw new Error('이 칸에서 학습할 아이콘을 분리하지 못했습니다.');
    const sampleDescriptor = descriptor(normalized);
    const normalizedRotation = ((Number(rotation) % 4) + 4) % 4;
    const matching = this.learned.filter((sample) => sample.itemId === itemId && sample.rotation === normalizedRotation);
    if (matching.some((sample) => descriptorDistance(sampleDescriptor, Uint8Array.from(sample.descriptor)) < 0.35)) {
      return;
    }
    while (matching.length >= 5) {
      const removalIndex = this.learned.findIndex((sample) => sample.itemId === itemId && sample.rotation === normalizedRotation);
      if (removalIndex < 0) break;
      this.learned.splice(removalIndex, 1);
      matching.shift();
    }
    this.learned.push({ itemId, rotation: normalizedRotation, descriptor: Array.from(sampleDescriptor), createdAt: Date.now() });
    this.saveLearned();
  }

  clearLearned() {
    this.learned = [];
    try { fs.unlinkSync(this.learnedFile); } catch {}
  }
}

module.exports = { Recognizer };
