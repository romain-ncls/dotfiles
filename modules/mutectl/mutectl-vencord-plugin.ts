import definePlugin from '@utils/types';
import { findByPropsLazy } from '@webpack';
import { MediaEngineStore } from '@webpack/common';

// Discord's audio actions: what its mute/deafen buttons, tray menu and keybinds call.
const AudioActions = findByPropsLazy('toggleSelfMute', 'toggleSelfDeaf');

function connect() {
  const eventSource = new EventSource('http://127.0.0.1:4815/sse');
  eventSource.addEventListener('error', () => {
    eventSource.close();
    setTimeout(connect, 1000);
  });
  eventSource.addEventListener('mute', () => {
    if (!MediaEngineStore.isSelfMute()) {
      AudioActions.toggleSelfMute();
    } else if (MediaEngineStore.isSelfDeaf()) {
      AudioActions.toggleSelfDeaf();
    }
  });
  eventSource.addEventListener('unmute', () => {
    if (MediaEngineStore.isSelfMute()) {
      AudioActions.toggleSelfMute();
    }
  });
  eventSource.addEventListener('afk', () => {
    if (!MediaEngineStore.isSelfMute()) {
      AudioActions.toggleSelfMute();
    }
    if (!MediaEngineStore.isSelfDeaf()) {
      AudioActions.toggleSelfDeaf();
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
