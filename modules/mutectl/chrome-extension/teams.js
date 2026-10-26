let eventSource;
let retryTimer;
let connected;

function getMuteBtn() {
  return document.querySelector('#microphone-button')
}

// The extension was reloaded or removed: this copy of the script must stop,
// or it would click the button along with the new one.
function orphaned() {
  return !chrome.runtime?.id;
}

// Tells background.js, which shows it as a dot on the toolbar icon.
function report(state) {
  if (state === connected || orphaned()) return;
  connected = state;
  chrome.runtime.sendMessage({ connected }).catch(() => {});
}

function onEvent(handler) {
  return () => {
    if (orphaned()) {
      eventSource.close();
      clearTimeout(retryTimer);
      return;
    }
    handler();
  };
}

function connect() {
  clearTimeout(retryTimer);
  eventSource?.close();
  eventSource = new EventSource('http://127.0.0.1:4815/sse');
  eventSource.addEventListener('open', () => report(true));
  eventSource.addEventListener('error', () => {
    report(false);
    eventSource.close();
    if (!orphaned()) {
      retryTimer = setTimeout(connect, 1000);
    }
  });
  // Teams has no deafen: AFK only mutes
  for (const event of ['mute', 'afk']) {
    eventSource.addEventListener(event, onEvent(() => {
      const btn = getMuteBtn()
      if (btn?.dataset.state == 'mic') {
        btn.click()
      }
    }));
  }
  eventSource.addEventListener('unmute', onEvent(() => {
    const btn = getMuteBtn()
    if (btn?.dataset.state == 'mic-off') {
      btn.click()
    }
  }));
}

// Clicking the toolbar icon reconnects now, without waiting for the retry.
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg === 'reconnect') {
    connected = undefined;
    connect();
    sendResponse(true);
  }
});

connect()
