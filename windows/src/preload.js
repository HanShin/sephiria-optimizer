const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('sephiria', {
  bootstrap: () => ipcRenderer.invoke('bootstrap'),
  captureGame: (sourceId) => ipcRenderer.invoke('capture-game', sourceId),
  saveCalibration: (rect) => ipcRenderer.invoke('save-calibration', rect),
  setSlotCount: (value) => ipcRenderer.invoke('set-slot-count', value),
  setAlwaysOnTop: (value) => ipcRenderer.invoke('set-always-on-top', value),
  recognize: (payload) => ipcRenderer.invoke('recognize', payload),
  learnItem: (payload) => ipcRenderer.invoke('learn-item', payload),
  clearLearning: () => ipcRenderer.invoke('clear-learning'),
  optimizeLayout: (layout) => ipcRenderer.invoke('optimize-layout', layout),
  onHotkeyCapture: (callback) => {
    const listener = () => callback();
    ipcRenderer.on('hotkey-capture', listener);
    return () => ipcRenderer.removeListener('hotkey-capture', listener);
  }
});
