import definePlugin from '@utils/types';

function getMuteBtn(): HTMLButtonElement {
  return document.querySelector('div[class*="audioButtonParent"]:first-of-type > button[role="switch"]') as HTMLButtonElement
}

function getAfkButton(): HTMLButtonElement {
  return document.querySelector('div[class*="audioButtonParent"]:last-of-type > button[role="switch"]') as HTMLButtonElement
}

function connect() {
  const eventSource = new EventSource('http://127.0.0.1:4815/sse');
  eventSource.addEventListener('error', () => {
    eventSource.close();
    setTimeout(connect, 1000);
  });
  eventSource.addEventListener('mute', () => {
    const btn = getMuteBtn()
    if (btn.ariaChecked == 'false') {
      btn.click()
    } else {
      const afkBtn = getAfkButton()
      if (afkBtn.ariaChecked == 'true') {
        afkBtn.click()
      }
    }
  });
  eventSource.addEventListener('unmute', () => {
    const btn = getMuteBtn()
    if (btn.ariaChecked == 'true') {
      btn.click()
    }

  });
  eventSource.addEventListener('afk', () => {
    const muteBtn = getMuteBtn()
    const afkBtn = getAfkButton()
    if (muteBtn.ariaChecked == 'false') {
      muteBtn.click()
    }
    if (afkBtn.ariaChecked == 'false') {
      afkBtn.click()
    }
  });
}

export default definePlugin({
  name: 'MuteCtl',
  description: 'Plugin to control Discord mute state an external service.',
  authors: [{ name: 'romainncls', id: 1274990984953856011n }],
  enabledByDefault: true,

  start() {
    connect();
  },
});
