// Shows each Teams tab's connection to mutectl-service as a dot on the
// toolbar icon, and reconnects it when the icon is clicked.

const ICONS = { 16: 'icons/icon-16.png', 32: 'icons/icon-32.png' };
const TEAMS = ['https://teams.cloud.microsoft/*', 'https://teams.microsoft.com/*'];

const STATES = {
  true: { dot: '#22C55E', title: 'mutectl: connected' },
  false: { dot: '#EF4444', title: 'mutectl: not connected, click to retry' },
};

const drawn = {};

// The icon with a dot in its top-right corner, at each toolbar size.
async function drawIcon(color) {
  const imageData = {};
  for (const [size, path] of Object.entries(ICONS)) {
    const blob = await (await fetch(chrome.runtime.getURL(path))).blob();
    const canvas = new OffscreenCanvas(size, size);
    const ctx = canvas.getContext('2d');
    ctx.drawImage(await createImageBitmap(blob), 0, 0, size, size);
    // In the corner, clear of the mic, with a transparent ring around it.
    const r = size * 0.16;
    const x = size - r - size / 32;
    const y = size - x;
    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath();
    ctx.arc(x, y, r + size / 16, 0, 2 * Math.PI);
    ctx.fill();
    ctx.globalCompositeOperation = 'source-over';
    ctx.beginPath();
    ctx.arc(x, y, r, 0, 2 * Math.PI);
    ctx.fillStyle = color;
    ctx.fill();
    imageData[size] = ctx.getImageData(0, 0, size, size);
  }
  return imageData;
}

chrome.runtime.onMessage.addListener(async (msg, sender) => {
  const tabId = sender.tab?.id;
  if (tabId === undefined || !('connected' in msg)) return;
  const state = STATES[msg.connected];
  drawn[msg.connected] ??= drawIcon(state.dot);
  await chrome.action.setIcon({ tabId, imageData: await drawn[msg.connected] });
  await chrome.action.setTitle({ tabId, title: state.title });
});

chrome.action.onClicked.addListener(async (tab) => {
  try {
    await chrome.tabs.sendMessage(tab.id, 'reconnect');
  } catch {
    // No script in the tab: it was opened before the extension was (re)loaded.
    // Fails, harmlessly, on tabs that aren't Teams.
    await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ['teams.js'] }).catch(() => {});
  }
});

// After an install or reload, give the open Teams tabs a fresh script; the
// old one notices it is orphaned and stops.
chrome.runtime.onInstalled.addListener(async () => {
  for (const tab of await chrome.tabs.query({ url: TEAMS })) {
    chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ['teams.js'] }).catch(() => {});
  }
});
