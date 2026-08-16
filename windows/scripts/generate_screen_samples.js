const fs = require('node:fs');
const path = require('node:path');
const {
  cellImages,
  decodePng,
  descriptor,
  detectedKind,
  normalizeCell,
  resizeNearest
} = require('../src/image');

const fixture = path.join(__dirname, '..', 'test', 'fixtures', 'live-inventory.png');
const output = path.join(__dirname, '..', 'resources', 'screen-samples.json');
const expected = new Map([
  ['0-2', 'artifact:amulet'],
  ['1-0', 'artifact:snowborne'],
  ['1-1', 'artifact:ice_star'],
  ['1-2', 'tablet:harvesting'],
  ['1-3', 'artifact:pro'],
  ['2-2', 'artifact:small_magic']
]);
const rect = { x: 431 / 1365, y: 200 / 768, width: 516 / 1365, height: 333 / 768 };
const image = decodePng(fs.readFileSync(fixture));
const cells = cellImages(image, rect, 20);
const samples = [];

for (const [position, itemId] of expected) {
  const cell = cells.get(position);
  const kind = detectedKind(cell);
  const normalized = normalizeCell(resizeNearest(cell, 96, 96), kind);
  if (!normalized) throw new Error(`${position} 아이콘을 정규화하지 못했습니다.`);
  samples.push({ itemId, rotation: 0, descriptor: Array.from(descriptor(normalized)) });
}

fs.writeFileSync(output, `${JSON.stringify(samples)}\n`);
console.log(`${samples.length}개 화면 샘플 생성: ${output}`);
