// Sends the active tab to the desktop app, together with the cookies that
// authenticate it.
//
// The whole point of the extension is that the browser has a session the app
// cannot get at: reading Chrome's cookie database from outside stopped working
// with App-Bound Encryption in Chrome 127, and a captcha result only exists in
// the browser that solved it. Here, chrome.cookies hands it over directly.

const DEFAULTS = { port: 47823, token: "" };

async function readConfig() {
  const stored = await chrome.storage.local.get(DEFAULTS);
  return {
    port: Number(stored.port) || DEFAULTS.port,
    token: stored.token || "",
  };
}

// Only cookies the browser would itself send to this page. A broader sweep by
// domain would rake in unrelated sites' sessions and write them to disk, which
// is not something a download button should be doing.
async function cookiesFor(url) {
  const cookies = await chrome.cookies.getAll({ url });
  return cookies.map((c) => ({
    domain: c.domain,
    name: c.name,
    value: c.value,
    path: c.path,
    secure: c.secure,
    httpOnly: c.httpOnly,
    hostOnly: c.hostOnly,
    expirationDate: c.expirationDate,
  }));
}

// The toolbar button has no popup, so the badge is the only channel for saying
// what happened. It clears itself so a stale mark is never mistaken for the
// result of the next click.
let badgeTimer = null;
function flashBadge(text, color) {
  chrome.action.setBadgeBackgroundColor({ color });
  chrome.action.setBadgeText({ text });
  if (badgeTimer) clearTimeout(badgeTimer);
  badgeTimer = setTimeout(() => chrome.action.setBadgeText({ text: "" }), 4000);
}

function reportFailure(message) {
  flashBadge("!", "#c62828");
  chrome.action.setTitle({ title: `Video Downloader: ${message}` });
}

async function send(tab) {
  if (!tab || !tab.url || !/^https?:/i.test(tab.url)) {
    reportFailure("this page cannot be downloaded from.");
    return;
  }

  const { port, token } = await readConfig();
  if (!token) {
    reportFailure("no pairing key set. Open the extension's options.");
    chrome.runtime.openOptionsPage();
    return;
  }

  let response;
  try {
    response = await fetch(`http://127.0.0.1:${port}/add`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-auth-token": token,
      },
      body: JSON.stringify({
        url: tab.url,
        title: tab.title,
        cookies: await cookiesFor(tab.url),
        // Sent so yt-dlp presents the same identity that earned the cookies —
        // Cloudflare ties the clearance it issues to the User-Agent, so a
        // mismatch throws away the captcha the user just solved.
        userAgent: navigator.userAgent,
        referer: tab.url,
      }),
    });
  } catch (e) {
    reportFailure("the app is not running, or the bridge is switched off.");
    return;
  }

  if (response.status === 401) {
    reportFailure("the pairing key does not match the app's.");
    return;
  }
  if (!response.ok) {
    reportFailure(`the app refused the link (HTTP ${response.status}).`);
    return;
  }

  flashBadge("✓", "#2e7d32");
  chrome.action.setTitle({ title: "Send this page to Video Downloader" });
}

chrome.action.onClicked.addListener(send);
