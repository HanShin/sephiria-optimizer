function positionKey(row, column) {
  return `${row}-${column}`;
}

function parsePosition(key) {
  const [row, column] = key.split('-').map(Number);
  return { row, column };
}

function gridPositions(slotCount) {
  return Array.from({ length: slotCount }, (_, index) => ({
    row: Math.floor(index / 6),
    column: index % 6,
    key: positionKey(Math.floor(index / 6), index % 6)
  }));
}

function rowCount(slotCount) {
  return Math.ceil(slotCount / 6);
}

function contains(slotCount, position) {
  return position.row >= 0 && position.column >= 0 && position.column < 6
    && position.row * 6 + position.column < slotCount;
}

function rotateOffset(dx, dy, rotation) {
  switch (((rotation % 4) + 4) % 4) {
    case 1: return { dx: -dy, dy: dx };
    case 2: return { dx: -dx, dy: -dy };
    case 3: return { dx: dy, dy: -dx };
    default: return { dx, dy };
  }
}

function effectMap(layout, catalogById) {
  const positions = gridPositions(layout.slotCount);
  const bonuses = Object.fromEntries(positions.map(({ key }) => [key, 0]));
  const ignoredConditions = new Set();
  const add = (offsets, origin, rotation = 0) => {
    for (const offset of offsets) {
      const transformed = rotateOffset(offset.dx, offset.dy, rotation);
      const target = { row: origin.row + transformed.dy, column: origin.column + transformed.dx };
      if (!contains(layout.slotCount, target)) continue;
      const key = positionKey(target.row, target.column);
      bonuses[key] = (bonuses[key] || 0) + (offset.value ?? 1);
      if (offset.ignore) ignoredConditions.add(key);
    }
  };
  const o = (dx, dy, value = 1, ignore = false) => ({ dx, dy, value, ignore });

  for (const [key, piece] of Object.entries(layout.pieces || {})) {
    const item = catalogById.get(piece.itemId);
    if (!item || item.kind !== 'tablet') continue;
    const origin = parsePosition(key);
    const rotation = piece.rotation || 0;
    const id = item.tabletId;
    switch (id) {
      case 'approximation': add([o(0, -1), o(1, 0)], origin, rotation); break;
      case 'dry': add([o(0, -1), o(0, 1)], origin); break;
      case 'chivalry': add([o(-1, -2)], origin, rotation); break;
      case 'advent': add([o(0, -1), o(0, -2), o(0, 1, -1), o(0, 2, -1)], origin, rotation); break;
      case 'linear':
        if (origin.row === rowCount(layout.slotCount) - 1) add([o(-1, 0), o(1, 0)], origin);
        break;
      case 'sight': add([o(-1, -1), o(1, 1, -1)], origin, rotation); break;
      case 'handshake': add([o(0, -1), o(0, 1)], origin, rotation); break;
      case 'fate': add([o(0, 1)], origin); break;
      case 'wit': add([o(-1, -1)], origin, rotation); break;
      case 'exploitation': add([o(0, -1), o(0, 1, -1)], origin, rotation); break;
      case 'unity': add([o(1, 0), o(0, 1), o(0, -1, -1), o(-1, 0, -1)], origin, rotation); break;
      case 'cheer': add([o(0, -1)], origin); break;
      case 'hope': add([o(1, 0)], origin, rotation); break;
      case 'compete': add([o(0, 1, 3), o(0, -1, -1), o(-1, -1, -1)], origin, rotation); break;
      case 'beating': add([o(0, -2, 2)], origin, rotation); break;
      case 'home_town': add([o(1, 0, 0, true)], origin, rotation); break;
      case 'past': add([o(-1, -1), o(0, -1), o(1, -1), o(1, 0)], origin, rotation); break;
      case 'future': add([o(-1, -1), o(0, -1), o(1, -1), o(-1, 0)], origin, rotation); break;
      case 'distribution': add([o(0, -1), o(-1, 0), o(1, 0), o(0, 1)], origin); break;
      case 'triceps': add([o(0, -1), o(-1, 0), o(1, 0)], origin); break;
      case 'harvesting': add([o(0, 1, 2), o(0, -1, 2)], origin, rotation); break;
      case 'binary_star': add([o(0, 2, 2), o(0, -2, 2)], origin, rotation); break;
      case 'nurture': add([o(-1, -1), o(0, -1), o(1, -1), o(0, 1, -1), o(0, 2, -1)], origin, rotation); break;
      case 'yearning': add([o(0, -1, 2)], origin); break;
      case 'agglutination':
        for (const position of positions) {
          if (position.key === key) continue;
          if (rotation % 2 === 1 && position.column === origin.column) bonuses[position.key] -= 1;
          if (rotation % 2 === 0 && position.row === origin.row) bonuses[position.key] -= 1;
        }
        add([o(0, -1, 3)], origin, rotation);
        break;
      case 'entrance': add([o(0, -1, 2), o(-1, -1), o(1, -1)], origin); break;
      case 'joke': add([o(0, -1), o(1, -1), o(-1, -1), o(-1, 0, -1), o(1, 0, -1)], origin, rotation); break;
      case 'load': add([o(0, -1), o(-1, -1), o(0, -2), o(-1, -2)], origin, rotation); break;
      case 'transition': {
        const rowValue = rotation % 2 === 1 ? -1 : 1;
        const columnValue = -rowValue;
        for (const position of positions) {
          if (position.key === key) continue;
          if (position.row === origin.row) bonuses[position.key] += rowValue;
          if (position.column === origin.column) bonuses[position.key] += columnValue;
        }
        break;
      }
      case 'advance': add([o(0, -1), o(0, -2), o(0, -3)], origin, rotation); break;
      case 'justice': {
        const row = positions.filter((position) => position.row === origin.row);
        if (origin.column === row[0]?.column || origin.column === row[row.length - 1]?.column) {
          for (const position of positions) {
            if (position.column === origin.column && position.key !== key) bonuses[position.key] += 1;
          }
        }
        break;
      }
      case 'preparation': add([o(-1, -1), o(1, 1, 2)], origin, rotation); break;
      case 'exit': add([o(-1, 1), o(0, 1, 2), o(1, 1)], origin); break;
      case 'tide': add([o(1, -1, 3), o(0, -1, -1), o(1, 0, -1)], origin, rotation); break;
      case 'dedication': add([o(1, -1), o(-1, -1), o(1, 1), o(-1, 1)], origin); break;
      case 'honor': add([o(0, -1, 2), o(-1, -2)], origin, rotation); break;
      case 'rally': add([o(0, -1, 2), o(-1, 0, 2)], origin, rotation); break;
      case 'development': add([o(-1, -1, 2), o(0, -1), o(-1, 0)], origin, rotation); break;
      case 'base':
        for (const position of positions) {
          if (position.row === origin.row && position.key !== key) bonuses[position.key] += 1;
        }
        break;
      case 'warrant': add([o(0, -1, 3)], origin, rotation); break;
      case 'wedge': add([o(-1, -1, 3)], origin, rotation); break;
      case 'disconnection': add([o(0, -1, 3), o(0, 1, 3), o(1, 0, -1), o(-1, 0, -1)], origin); break;
      case 'concurrency':
        for (const position of positions) {
          if (position.column === origin.column && position.key !== key) bonuses[position.key] += 1;
        }
        break;
      case 'vow': add([o(0, -2, 2), o(0, 1), o(0, -1), o(-1, 0), o(1, 0)], origin, rotation); break;
      case 'rebellion': {
        const direction = rotation % 2 === 1 ? -1 : 1;
        for (const [dx, dy] of [[direction, -1], [-direction, 1]]) {
          let cursor = { ...origin };
          while (true) {
            cursor = { row: cursor.row + dy, column: cursor.column + dx };
            if (!contains(layout.slotCount, cursor)) break;
            bonuses[positionKey(cursor.row, cursor.column)] += 1;
          }
        }
        break;
      }
      case 'connection': add([o(0, -1, 2), o(0, 1, 0, true)], origin, rotation); break;
      case 'junction': add([o(0, -1), o(0, -2), o(0, -3), o(1, 0), o(2, 0), o(3, 0)], origin, rotation); break;
      case 'last_stand': add([o(0, -1, 5), o(-1, 0, -1), o(1, 0, -1), o(0, 1, -1)], origin); break;
      case 'flag':
        if (origin.column === 0) add([o(0, -1), o(1, 0), o(2, 0, 2), o(3, 0, 3), o(0, 1, -1)], origin);
        break;
      case 'defender': add([o(-1, -1), o(1, -1, 2), o(-1, 0, -1), o(1, 0, -1), o(-1, 1, 2), o(1, 1)], origin); break;
      case 'shade': {
        if (origin.row !== 0 || rowCount(layout.slotCount) < 2) break;
        const lastRow = rowCount(layout.slotCount) - 1;
        const previousRow = lastRow - 1;
        const bottom = positions.filter((position) => position.row === lastRow);
        const bottomColumns = new Set(bottom.map((position) => position.column));
        for (const position of bottom) bonuses[position.key] += 1;
        for (const position of positions) {
          if (position.row === previousRow && !bottomColumns.has(position.column)) bonuses[position.key] += 1;
        }
        break;
      }
      case 'thorn': add([o(0, -1, 2), o(0, 1, 2), o(-1, -1), o(-1, 0), o(-1, 1), o(1, -1), o(1, 0), o(1, 1)], origin); break;
      case 'boundary': {
        const lastRow = rowCount(layout.slotCount) - 1;
        const first = positions.filter((position) => position.row === 0);
        const last = positions.filter((position) => position.row === lastRow);
        for (const position of [...first, ...last]) bonuses[position.key] += 1;
        if (lastRow > 0) {
          const lastColumns = new Set(last.map((position) => position.column));
          for (const position of positions) {
            if (position.row === lastRow - 1 && !lastColumns.has(position.column)) bonuses[position.key] += 1;
          }
        }
        break;
      }
      case 'sheen':
        for (const position of positions) {
          if (position.key === key) continue;
          if (rotation % 2 === 1 && position.column === origin.column) bonuses[position.key] += 1;
          if (rotation % 2 === 0 && position.row === origin.row) bonuses[position.key] += 1;
        }
        add([o(0, -1, 2), o(0, 1, 2)], origin, rotation);
        break;
      case 'miracle':
        for (const position of positions) {
          if (position.key === key) continue;
          if (position.row === origin.row) bonuses[position.key] += 1;
          if (position.column === origin.column) bonuses[position.key] += 1;
        }
        break;
      case 'daydream': add([o(-1, -1, 2), o(1, -1, 2), o(-1, 1, 2), o(1, 1, 2)], origin, rotation); break;
      case 'compression': add([o(0, -1, 3), o(0, -2, 2), o(0, -3)], origin, rotation); break;
      case 'certitude': add([o(0, -1, 5)], origin, rotation); break;
      case 'hospitality': add([o(0, -1, 1, true), o(-1, 0, 2, true)], origin); break;
      case 'peace': add([o(-1, 0, 3), o(1, 0, 3)], origin, rotation); break;
      case 'courage': add([o(-3, -3), o(-2, -2), o(-1, -1), o(1, 1), o(2, 2), o(1, -1, 2), o(-1, 1, 2)], origin, rotation); break;
      default: break;
    }
  }
  return { bonuses, ignoredConditions };
}

function evaluate(layout, catalogById) {
  const effects = effectMap(layout, catalogById);
  const artifacts = [];
  let useful = 0;
  let full = 0;
  let positive = 0;
  let overflow = 0;
  let negative = 0;
  let ignored = 0;
  for (const [key, piece] of Object.entries(layout.pieces || {})) {
    const item = catalogById.get(piece.itemId);
    if (!item || item.kind !== 'artifact') continue;
    const amplification = effects.bonuses[key] || 0;
    const capacity = item.capacity || 0;
    const ignoresCondition = effects.ignoredConditions.has(key);
    artifacts.push({ key, name: item.name, amplification, capacity, overflow: Math.max(0, amplification - capacity), ignoresCondition });
    useful += Math.min(Math.max(amplification, 0), Math.max(capacity, 0));
    if (capacity > 0 && amplification === capacity) full += 1;
    if (amplification > 0) positive += 1;
    overflow += Math.max(0, amplification - capacity);
    negative += Math.max(0, -amplification);
    if (ignoresCondition) ignored += 1;
  }
  artifacts.sort((left, right) => left.key.localeCompare(right.key, undefined, { numeric: true }));
  return {
    artifacts,
    totalUsefulAmplification: useful,
    fullArtifactCount: full,
    positiveArtifactCount: positive,
    overflowAmount: overflow,
    negativeAmount: negative,
    ignoredConditionCount: ignored,
    score: -overflow * 100_000_000 + useful * 100_000 + full * 5_000 + positive * 500 + ignored * 100 - negative * 2_000,
    hasNoOverflow: overflow === 0
  };
}

function cloneLayout(layout) {
  return {
    slotCount: layout.slotCount,
    pieces: Object.fromEntries(Object.entries(layout.pieces || {}).map(([key, piece]) => [key, { ...piece }]))
  };
}

function createRandom(seed = Date.now()) {
  let value = seed >>> 0;
  return () => {
    value += 0x6D2B79F5;
    let next = value;
    next = Math.imul(next ^ (next >>> 15), next | 1);
    next ^= next + Math.imul(next ^ (next >>> 7), next | 61);
    return ((next ^ (next >>> 14)) >>> 0) / 4294967296;
  };
}

function shuffled(values, random) {
  const copy = [...values];
  for (let index = copy.length - 1; index > 0; index -= 1) {
    const target = Math.floor(random() * (index + 1));
    [copy[index], copy[target]] = [copy[target], copy[index]];
  }
  return copy;
}

function optimize(input, catalogById, options = {}) {
  const iterationsPerRestart = options.iterationsPerRestart || 4_000;
  const restartCount = options.restartCount || 4;
  const before = evaluate(input, catalogById);
  if (Object.keys(input.pieces || {}).length <= 1) {
    return { original: cloneLayout(input), optimized: cloneLayout(input), before, after: before, iterations: 0 };
  }
  const random = createRandom(options.seed);
  let bestLayout = cloneLayout(input);
  let bestEvaluation = before;
  let totalIterations = 0;
  const allPositions = gridPositions(input.slotCount).map((position) => position.key);

  for (let restart = 0; restart < Math.max(restartCount, 1); restart += 1) {
    let current;
    if (restart === 0) {
      current = cloneLayout(input);
    } else {
      const pieces = shuffled(Object.values(input.pieces).map((piece) => ({ ...piece })), random);
      const positions = shuffled(allPositions, random);
      current = { slotCount: input.slotCount, pieces: {} };
      pieces.forEach((piece, index) => {
        const item = catalogById.get(piece.itemId);
        if (item?.kind === 'tablet' && item.isRotatable) piece.rotation = Math.floor(random() * 4);
        current.pieces[positions[index]] = piece;
      });
    }
    let currentEvaluation = evaluate(current, catalogById);
    if (currentEvaluation.score > bestEvaluation.score) {
      bestLayout = cloneLayout(current);
      bestEvaluation = currentEvaluation;
    }

    for (let iteration = 0; iteration < Math.max(iterationsPerRestart, 1); iteration += 1) {
      totalIterations += 1;
      const progress = iteration / Math.max(iterationsPerRestart, 1);
      const temperature = Math.max(20, 35_000 * Math.pow(0.002, progress));
      const candidate = cloneLayout(current);
      if (random() < 0.78) {
        const first = allPositions[Math.floor(random() * allPositions.length)];
        let second = allPositions[Math.floor(random() * allPositions.length)];
        if (first === second) second = allPositions[(allPositions.indexOf(first) + 1) % allPositions.length];
        const firstPiece = candidate.pieces[first];
        const secondPiece = candidate.pieces[second];
        if (secondPiece) candidate.pieces[first] = secondPiece; else delete candidate.pieces[first];
        if (firstPiece) candidate.pieces[second] = firstPiece; else delete candidate.pieces[second];
      } else {
        const rotatable = Object.entries(candidate.pieces).filter(([, piece]) => {
          const item = catalogById.get(piece.itemId);
          return item?.kind === 'tablet' && item.isRotatable;
        });
        if (rotatable.length > 0) {
          const [key, piece] = rotatable[Math.floor(random() * rotatable.length)];
          candidate.pieces[key] = { ...piece, rotation: (piece.rotation + (random() < 0.5 ? 1 : 3)) % 4 };
        }
      }
      const candidateEvaluation = evaluate(candidate, catalogById);
      const delta = candidateEvaluation.score - currentEvaluation.score;
      if (delta >= 0 || Math.exp(delta / temperature) > random()) {
        current = candidate;
        currentEvaluation = candidateEvaluation;
      }
      if (candidateEvaluation.score > bestEvaluation.score) {
        bestLayout = cloneLayout(candidate);
        bestEvaluation = candidateEvaluation;
      }
    }
  }
  return { original: cloneLayout(input), optimized: bestLayout, before, after: bestEvaluation, iterations: totalIterations };
}

module.exports = { contains, effectMap, evaluate, gridPositions, optimize, parsePosition, positionKey, rotateOffset };
