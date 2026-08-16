const test = require('node:test');
const assert = require('node:assert/strict');
const { effectMap, evaluate, optimize } = require('../src/optimizer');

const artifact = {
  id: 'artifact:test',
  kind: 'artifact',
  name: '테스트 아티팩트',
  capacity: 1,
  isRotatable: false
};
const cheer = {
  id: 'tablet:cheer',
  tabletId: 'cheer',
  kind: 'tablet',
  name: '환호',
  capacity: 0,
  isRotatable: false
};
const warrant = {
  id: 'tablet:warrant',
  tabletId: 'warrant',
  kind: 'tablet',
  name: '권능',
  capacity: 0,
  isRotatable: true
};
const catalog = new Map([artifact, cheer, warrant].map((item) => [item.id, item]));

test('환호 석판은 바로 위 칸을 증폭한다', () => {
  const layout = {
    slotCount: 18,
    pieces: { '1-2': { itemId: cheer.id, rotation: 0 } }
  };
  const effects = effectMap(layout, catalog);
  assert.equal(effects.bonuses['0-2'], 1);
  assert.equal(effects.bonuses['2-2'], 0);
});

test('아티팩트 수용량을 넘은 증폭은 초과로 계산한다', () => {
  const layout = {
    slotCount: 18,
    pieces: {
      '0-0': { itemId: artifact.id, rotation: 0 },
      '1-0': { itemId: warrant.id, rotation: 0 }
    }
  };
  const result = evaluate(layout, catalog);
  assert.equal(result.totalUsefulAmplification, 1);
  assert.equal(result.overflowAmount, 2);
  assert.equal(result.hasNoOverflow, false);
});

test('최적화는 아이템을 보존하며 유효한 무초과 배치를 찾는다', () => {
  const input = {
    slotCount: 18,
    pieces: {
      '0-0': { itemId: artifact.id, rotation: 0 },
      '0-5': { itemId: cheer.id, rotation: 0 }
    }
  };
  const result = optimize(input, catalog, {
    seed: 42,
    iterationsPerRestart: 800,
    restartCount: 2
  });
  assert.equal(Object.keys(result.optimized.pieces).length, 2);
  assert.equal(result.after.hasNoOverflow, true);
  assert.ok(result.after.totalUsefulAmplification >= 1);
});
