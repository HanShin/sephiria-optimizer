const { app, BrowserWindow, desktopCapturer, globalShortcut, ipcMain } = require('electron');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { loadCatalog } = require('./catalog');
const { optimize } = require('./optimizer');
const { Recognizer } = require('./recognizer');

let mainWindow;
let catalog;
let catalogById;
let recognizer;
let settings;

if (process.env.SEPHIRIA_SMOKE_SCREENSHOT) {
  app.setPath('userData', path.join(os.tmpdir(), 'sephiria-optimizer-electron-smoke'));
}

function resourceDirectory() {
  return app.isPackaged
    ? path.join(process.resourcesPath, 'sephiria-resources')
    : path.join(__dirname, '..', 'resources');
}

function settingsFile() {
  return path.join(app.getPath('userData'), 'settings.json');
}

function loadSettings() {
  try {
    return {
      slotCount: 34,
      calibration: null,
      keepOnTop: true,
      preferredSourceId: null,
      ...JSON.parse(fs.readFileSync(settingsFile(), 'utf8'))
    };
  } catch {
    return { slotCount: 34, calibration: null, keepOnTop: true, preferredSourceId: null };
  }
}

function saveSettings() {
  fs.mkdirSync(path.dirname(settingsFile()), { recursive: true });
  const temporary = `${settingsFile()}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify(settings, null, 2));
  fs.renameSync(temporary, settingsFile());
}

function publicCatalog() {
  return catalog.map((item) => {
    const imagePath = path.join(resourceDirectory(), 'templates', `${item.templateKey}.png`);
    const imageDataUrl = `data:image/png;base64,${fs.readFileSync(imagePath).toString('base64')}`;
    return { ...item, imageDataUrl };
  });
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 1180,
    minHeight: 760,
    backgroundColor: '#17151d',
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });
  mainWindow.setMenuBarVisibility(false);
  mainWindow.setAlwaysOnTop(Boolean(settings.keepOnTop));
  mainWindow.loadFile(path.join(__dirname, 'index.html'));
  mainWindow.once('ready-to-show', async () => {
    const smokeScreenshot = process.env.SEPHIRIA_SMOKE_SCREENSHOT;
    if (smokeScreenshot) {
      if (process.env.SEPHIRIA_SMOKE_FIXTURE) {
        mainWindow.webContents.send('hotkey-capture');
        await delay(2_000);
      } else {
        await delay(500);
      }
      const image = await mainWindow.webContents.capturePage();
      fs.writeFileSync(smokeScreenshot, image.toPNG());
      app.quit();
      return;
    }
    mainWindow.show();
  });
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function captureGameWindow(preferredSourceId = null) {
  if (process.env.SEPHIRIA_SMOKE_FIXTURE) {
    const png = fs.readFileSync(process.env.SEPHIRIA_SMOKE_FIXTURE);
    return { requiresSource: false, sourceId: 'smoke', sourceName: 'Sephiria smoke fixture', imageDataUrl: `data:image/png;base64,${png.toString('base64')}` };
  }
  const wasVisible = mainWindow?.isVisible();
  if (wasVisible) mainWindow.hide();
  await delay(220);
  try {
    const sources = await desktopCapturer.getSources({
      types: ['window'],
      thumbnailSize: { width: 4096, height: 2304 },
      fetchWindowIcons: false
    });
    const usable = sources.filter((source) => {
      const name = source.name.toLocaleLowerCase();
      return !name.includes('sephiria optimizer') && !source.thumbnail.isEmpty();
    });
    const selected = usable.find((source) => source.id === preferredSourceId)
      || usable.find((source) => {
        const name = source.name.toLocaleLowerCase();
        return name.includes('sephiria') || name.includes('세피리아');
      });
    if (!selected) {
      return {
        requiresSource: true,
        sources: usable.map((source) => ({
          id: source.id,
          name: source.name,
          previewDataUrl: source.thumbnail.resize({ width: 240 }).toDataURL()
        }))
      };
    }
    const png = selected.thumbnail.toPNG();
    if (!png.length) throw new Error('게임 창 이미지를 가져오지 못했습니다. 창이 최소화되어 있지 않은지 확인해 주세요.');
    settings.preferredSourceId = selected.id;
    saveSettings();
    return { requiresSource: false, sourceId: selected.id, sourceName: selected.name, imageDataUrl: `data:image/png;base64,${png.toString('base64')}` };
  } finally {
    if (wasVisible && mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show();
      mainWindow.focus();
    }
  }
}

function installIpcHandlers() {
  ipcMain.handle('bootstrap', () => ({ settings, catalog: publicCatalog() }));
  ipcMain.handle('capture-game', (_event, sourceId) => captureGameWindow(sourceId || settings.preferredSourceId));
  ipcMain.handle('save-calibration', (_event, rect) => {
    settings.calibration = rect;
    saveSettings();
    return settings;
  });
  ipcMain.handle('set-slot-count', (_event, value) => {
    settings.slotCount = Math.min(60, Math.max(18, Number(value) || 34));
    saveSettings();
    return settings.slotCount;
  });
  ipcMain.handle('set-always-on-top', (_event, value) => {
    settings.keepOnTop = Boolean(value);
    mainWindow.setAlwaysOnTop(settings.keepOnTop);
    saveSettings();
    return settings.keepOnTop;
  });
  ipcMain.handle('recognize', (_event, payload) => {
    const result = recognizer.recognize(payload.imageDataUrl, payload.calibration, payload.slotCount);
    settings.slotCount = result.slotCount;
    saveSettings();
    return result;
  });
  ipcMain.handle('learn-item', (_event, payload) => {
    recognizer.learn(payload.itemId, payload.rotation || 0, payload.cellDataUrl);
    return true;
  });
  ipcMain.handle('clear-learning', () => {
    recognizer.clearLearned();
    return true;
  });
  ipcMain.handle('optimize-layout', (_event, layout) => optimize(layout, catalogById));
}

app.whenReady().then(() => {
  settings = loadSettings();
  if (process.env.SEPHIRIA_SMOKE_FIXTURE) {
    settings.slotCount = 34;
    settings.calibration = { x: 431 / 1365, y: 200 / 768, width: 516 / 1365, height: 333 / 768 };
  }
  catalog = loadCatalog(resourceDirectory());
  catalogById = new Map(catalog.map((item) => [item.id, item]));
  recognizer = new Recognizer(catalog, resourceDirectory(), app.getPath('userData'));
  installIpcHandlers();
  createWindow();
  for (const accelerator of ['F8', 'Alt+CommandOrControl+I']) {
    globalShortcut.register(accelerator, () => {
      if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('hotkey-capture');
    });
  }
});

app.on('window-all-closed', () => app.quit());
app.on('will-quit', () => globalShortcut.unregisterAll());
