const { PNG } = require('pngjs');

function decodePng(buffer) {
  const png = PNG.sync.read(buffer);
  return { width: png.width, height: png.height, data: Buffer.from(png.data) };
}

function encodePng(image) {
  return PNG.sync.write({ width: image.width, height: image.height, data: Buffer.from(image.data) });
}

function toDataUrl(image) {
  return `data:image/png;base64,${encodePng(image).toString('base64')}`;
}

function bufferFromDataUrl(dataUrl) {
  const comma = dataUrl.indexOf(',');
  return Buffer.from(comma >= 0 ? dataUrl.slice(comma + 1) : dataUrl, 'base64');
}

function pixelIndex(image, x, y) {
  return (y * image.width + x) * 4;
}

function crop(image, x, y, width, height) {
  const left = Math.max(0, Math.min(image.width - 1, Math.round(x)));
  const top = Math.max(0, Math.min(image.height - 1, Math.round(y)));
  const right = Math.max(left + 1, Math.min(image.width, Math.round(x + width)));
  const bottom = Math.max(top + 1, Math.min(image.height, Math.round(y + height)));
  const output = {
    width: right - left,
    height: bottom - top,
    data: Buffer.alloc((right - left) * (bottom - top) * 4)
  };
  for (let row = 0; row < output.height; row += 1) {
    const sourceStart = pixelIndex(image, left, top + row);
    const destinationStart = row * output.width * 4;
    image.data.copy(output.data, destinationStart, sourceStart, sourceStart + output.width * 4);
  }
  return output;
}

function cropNormalized(image, rect) {
  return crop(
    image,
    rect.x * image.width,
    rect.y * image.height,
    rect.width * image.width,
    rect.height * image.height
  );
}

function resizeNearest(image, width, height) {
  const output = { width, height, data: Buffer.alloc(width * height * 4) };
  for (let y = 0; y < height; y += 1) {
    const sourceY = Math.min(image.height - 1, Math.floor(y * image.height / height));
    for (let x = 0; x < width; x += 1) {
      const sourceX = Math.min(image.width - 1, Math.floor(x * image.width / width));
      const source = pixelIndex(image, sourceX, sourceY);
      const destination = pixelIndex(output, x, y);
      output.data[destination] = image.data[source];
      output.data[destination + 1] = image.data[source + 1];
      output.data[destination + 2] = image.data[source + 2];
      output.data[destination + 3] = image.data[source + 3];
    }
  }
  return output;
}

function rotateQuarterTurns(image, turns) {
  const normalizedTurns = ((turns % 4) + 4) % 4;
  if (normalizedTurns === 0) return image;
  const swapsDimensions = normalizedTurns % 2 === 1;
  const output = {
    width: swapsDimensions ? image.height : image.width,
    height: swapsDimensions ? image.width : image.height,
    data: Buffer.alloc(image.width * image.height * 4)
  };
  for (let y = 0; y < image.height; y += 1) {
    for (let x = 0; x < image.width; x += 1) {
      let destinationX;
      let destinationY;
      if (normalizedTurns === 1) {
        destinationX = image.height - 1 - y;
        destinationY = x;
      } else if (normalizedTurns === 2) {
        destinationX = image.width - 1 - x;
        destinationY = image.height - 1 - y;
      } else {
        destinationX = y;
        destinationY = image.width - 1 - x;
      }
      const source = pixelIndex(image, x, y);
      const destination = pixelIndex(output, destinationX, destinationY);
      image.data.copy(output.data, destination, source, source + 4);
    }
  }
  return output;
}

function median(values) {
  if (values.length === 0) return null;
  values.sort((a, b) => a - b);
  return values[Math.floor(values.length / 2)];
}

function connectedComponents(mask, width, height) {
  const visited = new Uint8Array(mask.length);
  const result = [];
  const directions = [
    [-1, -1], [0, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [0, 1], [1, 1]
  ];
  for (let start = 0; start < mask.length; start += 1) {
    if (!mask[start] || visited[start]) continue;
    visited[start] = 1;
    const queue = [start];
    const component = [];
    for (let cursor = 0; cursor < queue.length; cursor += 1) {
      const current = queue[cursor];
      component.push(current);
      const x = current % width;
      const y = Math.floor(current / width);
      for (const [dx, dy] of directions) {
        const nextX = x + dx;
        const nextY = y + dy;
        if (nextX < 0 || nextY < 0 || nextX >= width || nextY >= height) continue;
        const next = nextY * width + nextX;
        if (mask[next] && !visited[next]) {
          visited[next] = 1;
          queue.push(next);
        }
      }
    }
    result.push(component);
  }
  return result;
}

function normalizedFromMask(image, mask, regionPixelCount) {
  const components = connectedComponents(mask, image.width, image.height);
  if (components.length === 0) return null;
  components.sort((a, b) => b.length - a.length);
  const largest = components[0];
  if (largest.length < 8) return null;
  const minimumComponentSize = Math.max(3, Math.floor(largest.length / 12));
  const retained = components.filter((component) => component.length >= minimumComponentSize).flat();
  if (retained.length / Math.max(regionPixelCount, 1) < 0.012) return null;
  const xs = retained.map((index) => index % image.width);
  const ys = retained.map((index) => Math.floor(index / image.width));
  const minX = Math.min(...xs);
  const maxX = Math.max(...xs);
  const minY = Math.min(...ys);
  const maxY = Math.max(...ys);
  const sourceWidth = maxX - minX + 1;
  const sourceHeight = maxY - minY + 1;
  if (sourceWidth < 2 || sourceHeight < 2) return null;

  const outputSize = 96;
  const padding = 8;
  const usable = outputSize - padding * 2;
  const scale = Math.min(usable / sourceWidth, usable / sourceHeight);
  const drawWidth = Math.max(1, Math.floor(sourceWidth * scale));
  const drawHeight = Math.max(1, Math.floor(sourceHeight * scale));
  const offsetX = Math.floor((outputSize - drawWidth) / 2);
  const offsetY = Math.floor((outputSize - drawHeight) / 2);
  const output = { width: outputSize, height: outputSize, data: Buffer.alloc(outputSize * outputSize * 4) };
  for (let index = 3; index < output.data.length; index += 4) output.data[index] = 255;
  const retainedSet = new Set(retained);
  for (let y = 0; y < drawHeight; y += 1) {
    for (let x = 0; x < drawWidth; x += 1) {
      const sourceX = minX + Math.min(sourceWidth - 1, Math.floor(x / scale));
      const sourceY = minY + Math.min(sourceHeight - 1, Math.floor(y / scale));
      const sourcePixel = sourceY * image.width + sourceX;
      if (!retainedSet.has(sourcePixel)) continue;
      const source = sourcePixel * 4;
      const destination = pixelIndex(output, offsetX + x, offsetY + y);
      output.data[destination] = image.data[source];
      output.data[destination + 1] = image.data[source + 1];
      output.data[destination + 2] = image.data[source + 2];
    }
  }
  return output;
}

function normalizeTemplate(image) {
  const mask = new Uint8Array(image.width * image.height);
  for (let pixel = 0; pixel < mask.length; pixel += 1) {
    if (image.data[pixel * 4 + 3] >= 30) mask[pixel] = 1;
  }
  return normalizedFromMask(image, mask, image.width * image.height);
}

function normalizeCell(image, kind = null) {
  const minX = Math.max(0, Math.floor(image.width * 0.22));
  const maxX = Math.min(image.width - 1, Math.floor(image.width * (kind === 'artifact' ? 0.69 : 0.78)));
  const minY = Math.max(0, Math.floor(image.height * 0.22));
  const maxY = Math.min(image.height - 1, Math.floor(image.height * 0.78));
  const red = [];
  const green = [];
  const blue = [];
  for (let y = minY; y <= maxY; y += 1) {
    for (let x = minX; x <= maxX; x += 1) {
      const index = pixelIndex(image, x, y);
      red.push(image.data[index]);
      green.push(image.data[index + 1]);
      blue.push(image.data[index + 2]);
    }
  }
  const background = [median(red), median(green), median(blue)];
  if (background.some((value) => value === null)) return null;
  const mask = new Uint8Array(image.width * image.height);
  const thresholdSquared = 42 * 42;
  for (let y = minY; y <= maxY; y += 1) {
    for (let x = minX; x <= maxX; x += 1) {
      const relativeX = (x - minX) / Math.max(maxX - minX, 1);
      const relativeY = (y - minY) / Math.max(maxY - minY, 1);
      if (relativeX < 0.48 && (relativeY < 0.18 || relativeY > 0.82)) continue;
      if (kind === 'artifact' && relativeX > 0.64 && relativeY < 0.74) continue;
      const index = pixelIndex(image, x, y);
      if (image.data[index + 3] < 30) continue;
      const dr = image.data[index] - background[0];
      const dg = image.data[index + 1] - background[1];
      const db = image.data[index + 2] - background[2];
      if (dr * dr + dg * dg + db * db >= thresholdSquared) mask[y * image.width + x] = 1;
    }
  }
  return normalizedFromMask(image, mask, Math.max((maxX - minX + 1) * (maxY - minY + 1), 1));
}

function descriptor(image) {
  const resized = resizeNearest(image, 32, 32);
  const output = new Uint8Array(32 * 32 * 3);
  for (let pixel = 0; pixel < 32 * 32; pixel += 1) {
    output[pixel * 3] = resized.data[pixel * 4];
    output[pixel * 3 + 1] = resized.data[pixel * 4 + 1];
    output[pixel * 3 + 2] = resized.data[pixel * 4 + 2];
  }
  return output;
}

function descriptorDistance(left, right) {
  if (!left || !right || left.length !== right.length) return Number.POSITIVE_INFINITY;
  let total = 0;
  for (let index = 0; index < left.length; index += 1) {
    const difference = left[index] - right[index];
    total += difference * difference;
  }
  return Math.sqrt(total / left.length) / 255 * 100;
}

function raster(image, size = 40, preserveAlpha = false) {
  const resized = resizeNearest(image, size, size);
  const output = Buffer.from(resized.data);
  if (preserveAlpha) {
    for (let index = 0; index < output.length; index += 4) {
      const alpha = output[index + 3] / 255;
      output[index] = Math.round(output[index] * alpha);
      output[index + 1] = Math.round(output[index + 1] * alpha);
      output[index + 2] = Math.round(output[index + 2] * alpha);
    }
  } else {
    for (let index = 3; index < output.length; index += 4) output[index] = 255;
  }
  return { size, rgba: output };
}

function squaredColorDistance(red1, green1, blue1, red2, green2, blue2) {
  const red = red1 - red2;
  const green = green1 - green2;
  const blue = blue1 - blue2;
  return red * red + green * green + blue * blue;
}

function colorBin(red, green, blue) {
  const maximum = Math.max(red, green, blue);
  const minimum = Math.min(red, green, blue);
  if (maximum < 72) return 0;
  if (maximum - minimum < 28) return 1;
  if (blue > red * 1.15 && blue > green * 1.08) return 2;
  if (green > red * 1.10 && green > blue * 1.05) return 3;
  if (red > green * 1.10 && red > blue * 1.10) return 4;
  if (blue + green > red * 2.25) return 5;
  if (red + green > blue * 2.25) return 6;
  return 7;
}

function shapeDistance(template, target) {
  if (!template || !target || template.size !== target.size || template.rgba.length !== target.rgba.length) {
    return 100;
  }
  const size = target.size;
  const redSamples = [];
  const greenSamples = [];
  const blueSamples = [];
  for (let y = Math.floor(size * 0.18); y < Math.floor(size * 0.82); y += 1) {
    for (let x = Math.floor(size * 0.18); x < Math.floor(size * 0.82); x += 1) {
      const index = (y * size + x) * 4;
      redSamples.push(target.rgba[index]);
      greenSamples.push(target.rgba[index + 1]);
      blueSamples.push(target.rgba[index + 2]);
    }
  }
  const background = [median(redSamples), median(greenSamples), median(blueSamples)];
  if (background.some((value) => value === null)) return 100;
  const contrastThresholdSquared = 22 * 22;
  let best = 100;

  for (let offsetY = -1; offsetY <= 1; offsetY += 1) {
    for (let offsetX = -1; offsetX <= 1; offsetX += 1) {
      let templateCount = 0;
      let targetCount = 0;
      let intersection = 0;
      let colorError = 0;
      const templateHistogram = new Array(8).fill(0);
      const targetHistogram = new Array(8).fill(0);
      for (let y = 0; y < size; y += 1) {
        for (let x = 0; x < size; x += 1) {
          const normalizedX = x / size;
          const normalizedY = y / size;
          const cleanHead = normalizedX >= 0.16 && normalizedX <= 0.67
            && normalizedY >= 0.28 && normalizedY <= 0.74;
          const cleanHandle = normalizedX >= 0.42 && normalizedX <= 0.78
            && normalizedY >= 0.58 && normalizedY <= 0.82;
          if (!cleanHead && !cleanHandle) continue;
          const targetX = x + offsetX;
          const targetY = y + offsetY;
          if (targetX < 0 || targetY < 0 || targetX >= size || targetY >= size) continue;
          const templateIndex = (y * size + x) * 4;
          const targetIndex = (targetY * size + targetX) * 4;
          const alpha = template.rgba[templateIndex + 3] / 255;
          const templateRed = alpha > 0 ? Math.min(255, template.rgba[templateIndex] / alpha) : 0;
          const templateGreen = alpha > 0 ? Math.min(255, template.rgba[templateIndex + 1] / alpha) : 0;
          const templateBlue = alpha > 0 ? Math.min(255, template.rgba[templateIndex + 2] / alpha) : 0;
          const targetRed = target.rgba[targetIndex];
          const targetGreen = target.rgba[targetIndex + 1];
          const targetBlue = target.rgba[targetIndex + 2];
          const templateContrast = squaredColorDistance(
            templateRed, templateGreen, templateBlue,
            background[0], background[1], background[2]
          );
          const targetContrast = squaredColorDistance(
            targetRed, targetGreen, targetBlue,
            background[0], background[1], background[2]
          );
          const templateForeground = alpha >= 0.30 && templateContrast >= contrastThresholdSquared;
          const targetForeground = targetContrast >= contrastThresholdSquared;
          if (templateForeground) {
            templateCount += 1;
            templateHistogram[colorBin(templateRed, templateGreen, templateBlue)] += 1;
          }
          if (targetForeground) {
            targetCount += 1;
            targetHistogram[colorBin(targetRed, targetGreen, targetBlue)] += 1;
          }
          if (templateForeground && targetForeground) {
            intersection += 1;
            colorError += Math.sqrt(squaredColorDistance(
              templateRed, templateGreen, templateBlue,
              targetRed, targetGreen, targetBlue
            ) / 3) / 255;
          }
        }
      }
      if (templateCount <= 4 || targetCount <= 4 || intersection <= 0) continue;
      const dice = intersection * 2 / (templateCount + targetCount);
      const averageColorError = colorError / intersection;
      let histogramDistance = 0;
      for (let index = 0; index < templateHistogram.length; index += 1) {
        histogramDistance += Math.abs(
          templateHistogram[index] / templateCount - targetHistogram[index] / targetCount
        );
      }
      histogramDistance /= 2;
      best = Math.min(best, (1 - dice) * 55 + histogramDistance * 35 + averageColorError * 10);
    }
  }
  return best;
}

function detectedKind(image) {
  if (!normalizeCell(image, null)) return null;
  const minX = Math.floor(image.width * 0.05);
  const maxX = Math.floor(image.width * 0.46);
  const bandMin = Math.floor(image.height * 0.03);
  const bandMax = Math.floor(image.height * 0.22);
  const brightNeutralCount = (startY, endY) => {
    let count = 0;
    for (let y = startY; y <= endY; y += 1) {
      for (let x = minX; x <= maxX; x += 1) {
        const index = pixelIndex(image, x, y);
        const colors = [image.data[index], image.data[index + 1], image.data[index + 2]];
        const maximum = Math.max(...colors);
        const minimum = Math.min(...colors);
        if (maximum >= 165 && maximum - minimum <= 85) count += 1;
      }
    }
    return count;
  };
  const upper = brightNeutralCount(bandMin, bandMax);
  const lower = brightNeutralCount(image.height - bandMax - 1, image.height - bandMin - 1);
  return Math.max(upper, lower) >= 9 ? 'artifact' : 'tablet';
}

function slotEdgeScore(image) {
  if (image.width <= 2 || image.height <= 2) return 0;
  let total = 0;
  let comparisons = 0;
  for (let y = 1; y < image.height - 1; y += 1) {
    for (let x = 1; x < image.width - 1; x += 1) {
      const current = pixelIndex(image, x, y);
      const right = pixelIndex(image, x + 1, y);
      const down = pixelIndex(image, x, y + 1);
      for (let channel = 0; channel < 3; channel += 1) {
        total += Math.abs(image.data[current + channel] - image.data[right + channel]);
        total += Math.abs(image.data[current + channel] - image.data[down + channel]);
        comparisons += 2;
      }
    }
  }
  return comparisons > 0 ? total / comparisons : 0;
}

function rowCount(slotCount) {
  return Math.ceil(slotCount / 6);
}

function cellImages(image, inventoryRect, slotCount) {
  const inventory = cropNormalized(image, inventoryRect);
  const rows = rowCount(slotCount);
  const cellWidth = inventory.width / 6;
  const cellHeight = inventory.height / rows;
  const result = new Map();
  for (let index = 0; index < slotCount; index += 1) {
    const row = Math.floor(index / 6);
    const column = index % 6;
    const insetX = cellWidth * 0.015;
    const insetY = cellHeight * 0.015;
    result.set(`${row}-${column}`, crop(
      inventory,
      column * cellWidth + insetX,
      row * cellHeight + insetY,
      cellWidth - insetX * 2,
      cellHeight - insetY * 2
    ));
  }
  return result;
}

function detectSlotCount(image, inventoryRect) {
  const inventory = cropNormalized(image, inventoryRect);
  const estimatedRows = Math.min(10, Math.max(3, Math.round(inventory.height / inventory.width * 6)));
  const fullCount = estimatedRows * 6;
  if (fullCount < 18 || fullCount > 60) return null;
  const cells = cellImages(image, inventoryRect, fullCount);
  const baselineScores = [];
  for (let row = 0; row < estimatedRows - 1; row += 1) {
    for (let column = 0; column < 6; column += 1) {
      baselineScores.push(slotEdgeScore(cells.get(`${row}-${column}`)));
    }
  }
  baselineScores.sort((a, b) => a - b);
  if (baselineScores.length === 0) return null;
  const baseline = baselineScores[Math.floor(baselineScores.length / 2)];
  const threshold = Math.max(0.12, baseline * 0.34);
  let lastRowCount = 0;
  for (let column = 0; column < 6; column += 1) {
    if (slotEdgeScore(cells.get(`${estimatedRows - 1}-${column}`)) < threshold) break;
    lastRowCount += 1;
  }
  return lastRowCount > 0 ? (estimatedRows - 1) * 6 + lastRowCount : null;
}

module.exports = {
  bufferFromDataUrl,
  cellImages,
  cropNormalized,
  decodePng,
  descriptor,
  descriptorDistance,
  detectSlotCount,
  detectedKind,
  encodePng,
  normalizeCell,
  normalizeTemplate,
  raster,
  resizeNearest,
  rotateQuarterTurns,
  rowCount,
  shapeDistance,
  slotEdgeScore,
  toDataUrl
};
