function getMuteBtn() {
  return document.querySelector('#microphone-button')
}

function connect() {
  const eventSource = new EventSource('http://127.0.0.1:4815/sse');
  eventSource.addEventListener('error', () => {
    eventSource.close();
    setTimeout(connect, 1000);
  });
  eventSource.addEventListener('mute', () => {
    const btn = getMuteBtn()
    if (btn?.dataset.state == 'mic') {
      btn.click()
    }
  });
  eventSource.addEventListener('unmute', () => {
    const btn = getMuteBtn()
    if (btn?.dataset.state == 'mic-off') {
      btn.click()
    }
  });
}

connect()
