# Send to Video Downloader

`extension/` is a Manifest V3 browser extension for Chrome, Edge, and other
Chromium-based browsers. It sends the page in the active tab to the desktop app
with the cookies and browser identity that apply to that page.

Use it for videos that need a signed-in session or a recently solved captcha.
The desktop app receives the page, opens its usual quality picker (unless
**Always use best quality** is enabled), and queues the download.

## Install and pair

1. Build or run the desktop app, then open **Settings**.
2. Under **Browser extension**, turn on **Accept links from the browser
   extension**. The app starts its local listener on `127.0.0.1:47823` and
   shows a pairing key.
3. In Chrome or Edge, open `chrome://extensions` or `edge://extensions`, turn
   on **Developer mode**, then select **Load unpacked** and choose this
   `extension` directory.
4. Open the extension's **Options**, paste the pairing key, leave the port at
   `47823`, and select **Test connection**. A successful test says
   `Connected to the app.`

The pairing key is generated locally by the app and stored in its preferences.
If you generate a new key in Settings, paste the replacement into the extension
before sending another page.

## Use

1. Sign in to the site in your browser, or complete its captcha there.
2. Navigate to the page containing the video.
3. Click the extension's toolbar button.

A green check badge means the app accepted the page. A red `!` means it did
not; hover the toolbar button for the reason. The badge clears after a few
seconds.

## Data and permissions

The extension declares the `cookies` and `storage` permissions, plus host
access to the current page and the desktop app's loopback endpoint. Its broad
host permission is required by the current implementation so it can ask the
browser for cookies matching whichever page you click.

For each send, it reads **only the cookies the browser would send to that page**
and posts the following to `http://127.0.0.1:47823/add`:

- page URL and title;
- matching cookies, including HttpOnly and session cookies;
- the browser User-Agent; and
- the page URL as the referer.

The app writes received cookies to a Netscape-format jar in its per-user
`sessions` directory, one file per site. A new send for a site replaces that
site's previous jar. These jars are credentials: do not share or publish the
app support directory.

The extension stores only its pairing key and port in `chrome.storage.local`.
It does not upload data to a remote service, and the desktop app does not
include transcription or translation API integrations.

## Local security model

The desktop app listens on `127.0.0.1` only, never on a network interface. It
accepts requests only when all of the following are true:

- the request supplies the current pairing key in `x-auth-token`;
- its `Origin` is a Chrome or Firefox extension origin; and
- its `Host` is a loopback host.

The last two checks prevent an ordinary web page from driving the local port,
including through DNS rebinding. The pairing key comparison avoids revealing
partial matches through an early exit.

## Troubleshooting

| Message or symptom | What to do |
|---|---|
| `No answer` or `Not running / bridge switched off` | Start the desktop app and enable **Accept links from the browser extension** in Settings. |
| `Pairing key does not match` | Copy the current key from the app's Settings into the extension Options, then save. |
| `HTTP 403` or `app refused the link` | Keep the extension's port at `47823`; the desktop app currently uses that fixed local port. |
| The download is still refused | Refresh the page after signing in or solving the captcha, then send it again. A matching User-Agent is included automatically, but some sites use DRM or TLS/browser fingerprinting that cookies cannot satisfy. |

## Limits

- It cannot download DRM-protected streams.
- It does not bypass YouTube PO-token requirements; use yt-dlp's appropriate
  provider for those.
- It does not transcribe or translate media.
