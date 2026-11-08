// Posts the tabs that play sound to the sound menu's helper
// (config/quickshell/menus/audio-tabs.py), on every change, so it can name
// Brave's audio streams after their tabs.
const ENDPOINT = 'http://127.0.0.1:48231/tabs';
// Again now and then, for a helper that was restarted since the last change
const RESEND_ALARM = 'resend';
const RESEND_MINUTES = 0.5;

async function sendAudibleTabs() {
  const tabs = await chrome.tabs.query({ audible: true });
  const audible = tabs.map((tab) => ({ id: tab.id, title: tab.title ?? '' }));
  try {
    await fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(audible),
    });
  } catch (error) {
    // No desktop shell, or its helper is restarting: the next change or the
    // alarm sends again
    console.debug('Audio Tabs: helper not reached', error);
  }
}

chrome.tabs.onUpdated.addListener((tabId, change, tab) => {
  const isAudibleChange = change.audible !== undefined;
  const isTitleOfAudibleTab = change.title !== undefined && tab.audible === true;
  if (isAudibleChange || isTitleOfAudibleTab) {
    sendAudibleTabs();
  }
});
chrome.tabs.onRemoved.addListener(sendAudibleTabs);

chrome.alarms.create(RESEND_ALARM, { periodInMinutes: RESEND_MINUTES });
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === RESEND_ALARM) {
    sendAudibleTabs();
  }
});
chrome.runtime.onStartup.addListener(sendAudibleTabs);
chrome.runtime.onInstalled.addListener(sendAudibleTabs);
