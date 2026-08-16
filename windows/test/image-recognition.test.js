const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { loadCatalog } = require('../src/catalog');
const {
  cellImages,
  decodePng,
  detectSlotCount,
  detectedKind,
  resizeNearest,
  toDataUrl
} = require('../src/image');
const { Recognizer } = require('../src/recognizer');

const resourceDirectory = path.join(__dirname, '..', 'resources');
const fixture = path.join(__dirname, 'fixtures', 'live-inventory.png');
const rect = {
  x: 431 / 1365,
  y: 200 / 768,
  width: 516 / 1365,
  height: 333 / 768
};

test('실제 캡처에서 20칸과 6개 아이템을 구분한다', (context) => {
  if (!fs.existsSync(fixture)) context.skip('실제 인벤토리 캡처 fixture가 없습니다.');
  const image = decodePng(fs.readFileSync(fixture));
  assert.equal(detectSlotCount(image, rect), 20);
  const cells = cellImages(image, rect, 20);
  const occupied = [...cells.entries()]
    .filter(([, cell]) => detectedKind(cell))
    .map(([key]) => key)
    .sort();
  assert.deepEqual(occupied, ['0-2', '1-0', '1-1', '1-2', '1-3', '2-2']);
  assert.equal(detectedKind(cells.get('1-2')), 'tablet');
});

test('실제 아이콘 후보와 수동 학습이 해상도 변경 후에도 유지된다', (context) => {
  if (!fs.existsSync(fixture)) context.skip('실제 인벤토리 캡처 fixture가 없습니다.');
  const image = decodePng(fs.readFileSync(fixture));
  const cells = cellImages(image, rect, 20);
  const expected = new Map([
    ['0-2', 'artifact:amulet'],
    ['1-0', 'artifact:snowborne'],
    ['1-1', 'artifact:ice_star'],
    ['1-2', 'tablet:harvesting'],
    ['1-3', 'artifact:pro'],
    ['2-2', 'artifact:small_magic']
  ]);
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'sephiria-recognizer-'));
  const recognizer = new Recognizer(loadCatalog(resourceDirectory), resourceDirectory, temporary);
  recognizer.prepare();

  for (const [position, itemId] of expected) {
    const cell = cells.get(position);
    const candidates = recognizer.topMatches(cell, 24).map((match) => match.itemId);
    assert.ok(candidates.includes(itemId), `${position} 후보에 ${itemId}이(가) 없습니다.`);
    recognizer.learn(itemId, 0, toDataUrl(cell));
    const retinaCell = resizeNearest(cell, cell.width * 2, cell.height * 2);
    assert.equal(recognizer.topMatches(retinaCell, 1)[0]?.itemId, itemId);
  }
});

test('확인된 기본 화면 샘플은 오인식 없이 6개를 자동 확정한다', (context) => {
  if (!fs.existsSync(fixture)) context.skip('실제 인벤토리 캡처 fixture가 없습니다.');
  const catalog = loadCatalog(resourceDirectory);
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'sephiria-full-recognition-'));
  const recognizer = new Recognizer(catalog, resourceDirectory, temporary);
  const imageDataUrl = `data:image/png;base64,${fs.readFileSync(fixture).toString('base64')}`;
  const result = recognizer.recognize(imageDataUrl, rect, 34);
  assert.equal(result.slotCount, 20);
  assert.equal(result.detectedItemCount, 6);
  assert.deepEqual(result.unresolved, []);
  assert.deepEqual(
    Object.fromEntries(Object.entries(result.pieces).map(([key, piece]) => [key, piece.itemId])),
    {
      '0-2': 'artifact:amulet',
      '1-0': 'artifact:snowborne',
      '1-1': 'artifact:ice_star',
      '1-2': 'tablet:harvesting',
      '1-3': 'artifact:pro',
      '2-2': 'artifact:small_magic'
    }
  );
});
