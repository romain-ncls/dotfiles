import definePlugin from '@utils/types';

function getMuteBtn(): HTMLButtonElement {
  return document.querySelector('div[class*="micButtonParent"] > button') as HTMLButtonElement
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
    }
  });
  eventSource.addEventListener('unmute', () => {
    const btn = getMuteBtn()
    if (btn.ariaChecked == 'true') {
      btn.click()
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
