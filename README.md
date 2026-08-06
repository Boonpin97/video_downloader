# Video Downloader

A Windows desktop app for saving videos from streaming websites to watch offline.
Paste the address of a page that plays a video, pick a quality, and get an MP4.

It is a Flutter front-end over two external tools:

- **yt-dlp** finds the real media URL behind a site's JavaScript player. It maintains
  extractors for ~1800 sites plus a generic HLS/DASH fallback, and ships fixes when
  sites change.
- **FFmpeg** combines separate video and audio streams into a single MP4.

Both are downloaded automatically on first launch. Nothing needs to be installed by hand.

## What it can do

- Queue downloads, with a configurable limit of one to eight simultaneous jobs.
- Pause, resume, retry, cancel, and remove downloads. Partial data is retained for
  paused and failed jobs so yt-dlp can continue instead of starting over.
- Save video as MP4, or extract audio as MP3, M4A, Opus, WAV, or FLAC.
- Download and embed available subtitles in one or more yt-dlp language codes.
- Use a chosen output folder, an optional rate limit, saved cookie settings, and
  optional browser identity headers for sign-in-gated sites.
- Accept a page and its matching browser cookies from the bundled extension.

The app does not include transcription or translation services, nor does it
send media to a transcription or translation API.

**Out of scope:** DRM-protected streams (Widevine / PlayReady / FairPlay — Netflix,
Disney+, and similar). Those are detected and reported rather than failed cryptically.
Whether downloading from a given site is permitted is between you and that site's terms.

---

## 1. Prerequisites

Set these up before touching the project. Versions below are what the app is verified
against.

| Requirement | Version | Notes |
|---|---|---|
| Windows | 10 or 11, 64-bit | Verified on Windows 11 25H2 |
| Flutter SDK | **3.41.9+ stable** | Must include Dart **3.11.5+** |
| Visual Studio 2022 | Community is fine | **With the C++ workload — see below** |
| Git | any recent | Only needed to clone |
| Disk space | ~1.5 GB | SDK, packages, build output, and tools |
| Internet | required | For packages and the first-run tool download |

### The one that trips people up: Visual Studio

Flutter compiles Windows desktop apps with the **MSVC C++ toolchain**. Visual Studio
**Code is not sufficient** — it is a different product. You need Visual Studio 2022 with
the *Desktop development with C++* workload.

1. Install [Visual Studio 2022 Community](https://visualstudio.microsoft.com/downloads/).
2. In the installer, tick **Desktop development with C++**.
3. Under *Installation details*, confirm **MSVC v143 build tools** and **Windows 11 SDK**
   are selected. They are included by default.

Without this, `flutter build windows` fails with `Unable to find suitable Visual Studio
toolchain` and no amount of `pub get` will help.

### Dart version constraint

`pubspec.yaml` declares `sdk: ^3.11.5`. A Flutter older than 3.41.x ships an older Dart
and `flutter pub get` will refuse to resolve. Check with `flutter --version`; upgrade with
`flutter upgrade`.

### Confirm the toolchain

```powershell
flutter doctor
```

`[✓] Windows Version` and `[✓] Visual Studio - develop Windows apps` must both pass.
Android, Chrome, and web entries are irrelevant here and may show warnings safely.

---

## 2. Set up and build

From the project root:

```powershell
flutter pub get
flutter build windows --release
```

The first build compiles the C++ runner and takes a few minutes. Later builds are much
faster (~20s). The result lands in:

```
build\windows\x64\runner\Release\video_downloader.exe
```

---

## 3. First launch

```powershell
.\run.bat
```

`run.bat` starts the existing build without recompiling. It locates itself via `%~dp0`,
so it works from any directory or as a desktop shortcut. It prefers the Release build,
falls back to Debug, and tells you what to run if neither exists.

During development you can also use `flutter run -d windows`, which enables hot reload.

### What happens the first time

The app has no tools yet, so it shows a one-time setup screen and downloads them:

| Tool | Size | Source |
|---|---|---|
| `yt-dlp.exe` | ~17 MB | `github.com/yt-dlp/yt-dlp` latest release |
| `ffmpeg.exe` + `ffprobe.exe` | ~169 MB zip → ~275 MB extracted | `github.com/BtbN/FFmpeg-Builds` latest |

They are stored **per user**, not in the project:

```
%APPDATA%\com.pohboonpin\video_downloader\bin\
```

That location is deliberate. yt-dlp overwrites itself when you press **Update**, which is
impossible from `C:\Program Files`. Setup is a one-time cost — it is skipped on every
later launch, and a failed download is retried cleanly because files are written as
`.part` and renamed only once complete.

---

## 4. Verify the setup

```powershell
flutter analyze     # expect: No issues found!
flutter test        # expect: All tests passed!
```

The tests do not require internet access, yt-dlp, or FFmpeg. They cover parsing,
queue persistence and resuming, cookie-jar handling, and the local browser bridge.

To confirm the whole pipeline end to end, paste a URL from a site that streams video,
pick a quality, and check that:

1. the quality list appears (extraction works),
2. the progress bar **moves during** the download rather than jumping to 100% at the end,
3. the status becomes *Merging* before *Done* when video and audio are separate,
4. the finished file plays.

Point 2 matters most. If progress only appears at the end, the unbuffering described in
[How it works](#7-how-it-works) has broken.

---

## Download controls

Settings are saved between launches and apply to newly queued downloads:

| Control | Behaviour |
|---|---|
| **Save downloads to** | Defaults to the Windows Downloads known folder, but can be changed to any folder. |
| **Simultaneous downloads** | Runs 1-8 jobs at once; the default is 2. More jobs share the available bandwidth. |
| **Always use best quality** | Skips the format picker and chooses yt-dlp's best available stream. |
| **Speed limit** | Passes a yt-dlp limit such as `5M` or `500K`; leave it empty for no limit. |
| **Audio only** | Extracts audio in MP3, M4A, Opus, WAV, or FLAC rather than saving video. |
| **Download subtitles** | Downloads manual and automatic subtitles for comma-separated language codes (for example `en,ms`) and embeds them when available. |

Each queue item has its own pause, cancel, retry/resume, and remove controls. Pausing or
retrying preserves its partial data; cancelling or removing discards it. The queue itself
is restored at next launch, with jobs that were active when the app closed shown as paused.

---

## 5. Sites that need a sign-in or a captcha

Some videos are only reachable from an authenticated session. yt-dlp can borrow one, but
it has to be handed over — there are three ways, in increasing order of convenience.

**Read cookies from a browser** (*Settings → Site access*). The original mechanism, and
now the least reliable: Chrome 127 introduced App-Bound Encryption, which makes Chromium's
cookie database unreadable to any other process, closed browser or not. Still works with
Firefox.

**A `cookies.txt` file.** Sign in — or solve the captcha — in your browser, export a
Netscape-format cookie jar with an extension such as *Get cookies.txt LOCALLY*, and point
*Settings → Site access → Cookie file* at it. Works on every browser, and overrides the
browser option when both are set.

**The bundled browser extension** (`extension/`, see its own README). A toolbar button
sends the current page to the app together with its live cookies, so nothing has to be
exported by hand. Switch on *Settings → Browser extension*, copy the pairing key into the
extension's options page, and load the folder unpacked from `chrome://extensions`.

Whichever route, set **Browser identity** to your browser's User-Agent if a Cloudflare
challenge is involved. The `cf_clearance` cookie it issues is bound to the client IP *and*
the User-Agent, so a mismatch discards the challenge you just passed. The extension sends
this automatically.

None of this helps with DRM, or with YouTube's PO tokens — the latter need yt-dlp's
`bgutil` provider plugin rather than a session.

### How the bridge is secured

The extension reaches the app over HTTP on the loopback interface, rather than through a
native messaging host — the latter would need a registry-registered manifest pointing at a
stdio relay executable, which is a lot of installer machinery for a link and a cookie jar.
The trade-off is an open local port, so `core/link_server.dart` checks three things on
every request and all three are load-bearing:

- **The pairing key** (`x-auth-token`, compared without an early exit) proves the caller is
  the extension the user paired.
- **The `Origin`** must be `chrome-extension://` or `moz-extension://`, so an ordinary web
  page cannot drive the port even if it learns the key.
- **The `Host`** must be loopback. Without this, an attacker's domain that resolves to
  `127.0.0.1` would let their page's requests through — DNS rebinding.

The listener binds `127.0.0.1` only, never `0.0.0.0`, and is off until switched on.
Regenerating the key in Settings immediately revokes every extension holding the old one.

---

## 6. Project layout

```
lib/
  main.dart                  entry point, window sizing
  app.dart                   theme, providers, first-run gate
  core/
    paths.dart               per-user directories
    binaries.dart            download/locate/update yt-dlp + ffmpeg
    ytdlp_service.dart       probe() and download() subprocess wrappers
    progress_parser.dart     stdout line -> ProgressUpdate  (pure, unit-tested)
    queue_store.dart         queue persistence
    cookie_jar.dart          Netscape jar validation + rendering
    link_server.dart         loopback listener the extension posts to
    format_utils.dart        byte/speed/duration formatting
  models/
    video_info.dart          parsed `yt-dlp -J` output
    format_option.dart       one selectable stream
    download_task.dart       queue item + its live state
    download_options.dart    cookies, headers, subtitles, audio-only, rate limit
  state/
    queue_controller.dart    concurrency gate, cancel, retry
    settings_controller.dart persisted preferences
    bridge_controller.dart   link server lifecycle + status for the UI
  ui/
    first_run_page.dart      one-time tool download
    home_page.dart           paste box + queue, receives extension links
    format_picker_dialog.dart
    task_tile.dart           progress, speed, ETA, actions
    settings_page.dart
extension/                   MV3 browser extension (load unpacked)
  manifest.json
  background.js              toolbar click -> collect cookies -> POST /add
  options.html/.js           pairing key and port
test/
  link_server_test.dart      21 tests
  download_task_test.dart    15 tests
  progress_parser_test.dart  15 tests
  cookie_netscape_test.dart  11 tests
  download_options_test.dart 10 tests
  video_info_test.dart        9 tests
  cookie_jar_test.dart        6 tests
  settings_page_test.dart     1 test   guards the cross-route provider scoping
run.bat                      launch without rebuilding
```

---

## 7. How it works

**Probe.** `yt-dlp -J <url>` returns metadata as JSON, which becomes a `VideoInfo` with a
sorted format list for the picker.

**Download.** `yt-dlp` runs as a child process with a custom `--progress-template` that
emits parseable `DLPROG|…` lines. Partial fragments go to a per-task temp directory, so
cancelling is a single recursive delete rather than a guess at which `.part` files were
ours. The final path is captured via `--print-to-file after_move:filepath` into a sidecar
file, which keeps the progress stream clean.

Three details in `ytdlp_service.dart` are load-bearing and should not be removed:

- **`PYTHONUNBUFFERED=1`** — without it, Python block-buffers stdout when it has no TTY,
  and all progress arrives in one lump at the end. The bar appears frozen for the entire
  download.
- **`--ignore-config`** — stops a user's global `yt-dlp.conf` from injecting `--quiet` or
  its own `-o`, which would silently break progress parsing and output-path detection.
- **`--windows-filenames --trim-filenames 200`** — video titles routinely contain `:`,
  `?`, `|`, and `*`, all illegal in Windows paths, and long titles otherwise hit MAX_PATH
  late in the download.

**Pause and resume.** yt-dlp has no pause signal, so pausing means stopping the process
and *keeping* its scratch directory. yt-dlp writes a `.ytdl` file recording its fragment
position (`{"current_fragment": {"index": 3}}`) alongside the `.part` data, and `--continue`
picks up from there — at the fragment level for HLS, or via HTTP Range for direct files.

Three things make this work, and each is easy to break by accident:

- **Task ids are derived** (`sha1` of URL + format selector), not timestamps. The id names
  the scratch directory, so it must be reproducible or a resumed download could never find
  what it already fetched. A side effect is that queueing the same video twice resolves to
  the existing entry rather than two tasks fighting over one directory.
- **`taskTempDir()` never empties the directory.** It used to, which silently defeated
  every resume.
- **The scratch directory is deleted only on success, cancel, or remove** — never on pause
  or failure. A failed download therefore resumes on Retry instead of restarting, which
  matters on a flaky connection.

Only the page URL is stored, never the resolved media URL. Sites commonly sign media URLs
with a short-lived token, so resuming re-runs the extractor to get a fresh one. This is
what allows a download to be resumed days later.

**Progress.** On HLS — the most common case — `total_bytes` is never known and
`total_bytes_estimate` swings wildly (observed jumping 17 MB → 34 MB → 22 MB on one
stream), which would make the bar move backwards. So `progress_parser.dart` prefers, in
order: exact byte totals → fragment counts (monotonic) → the byte estimate. Estimated
sizes are shown with a `~` rather than presented as fact.

---

## 8. Troubleshooting

**`Unable to find suitable Visual Studio toolchain`**
The C++ workload is missing. See [Prerequisites](#the-one-that-trips-people-up-visual-studio).

**`flutter pub get` fails on the SDK constraint**
Flutter is too old for `sdk: ^3.11.5`. Run `flutter upgrade`.

**First-run download fails**
Usually a firewall or proxy blocking GitHub. You can place the tools manually — create
`%APPDATA%\com.pohboonpin\video_downloader\bin\` and drop in `yt-dlp.exe` and `ffmpeg.exe`
from their official releases. The app detects them and skips setup. *Settings* also lets
you point at an existing `ffmpeg.exe` anywhere on disk.

**"Could not find a video on that page"**
Almost always a stale extractor — sites change their players constantly. **Settings →
yt-dlp → Update** fixes most cases. To tell whether the fault is yt-dlp or this app, run
the extraction directly:

```powershell
& "$env:APPDATA\com.pohboonpin\video_downloader\bin\yt-dlp.exe" -J "<url>"
```

If that exits 0 and prints JSON, extraction works and the bug is in the app. If it errors,
update yt-dlp.

**The site refused access / private / members-only / captcha**
The request needs a session. See [Sites that need a sign-in or a
captcha](#5-sites-that-need-a-sign-in-or-a-captcha). On Chrome or Edge, *Use cookies from
browser* will not work — export a `cookies.txt` or use the extension instead.

**The extension's badge shows `!`**
Hover the toolbar button for the reason. *Not running / bridge switched off* means
**Settings → Browser extension** is off, or the app is closed. *Pairing key does not
match* means the key was regenerated in the app but not updated in the extension's
options. Nothing is logged to the app for a rejected request — that is deliberate, since
anything on the machine can reach the port.

**Progress bar jumps straight to 100%**
`PYTHONUNBUFFERED=1` is not reaching the child process. Check `_childEnvironment` in
`core/ytdlp_service.dart`.

**`run.bat` says "has not been built yet"**
`flutter clean` deletes `build\`. Rebuild with `flutter build windows --release`.

**Moving the app to another PC**
The exe depends on the DLLs and `data\` folder beside it — copy the whole `Release`
folder, not just the exe. A machine without Visual Studio also needs the
[Visual C++ Redistributable](https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist).

---

## 9. Where things live

| Path | Contents |
|---|---|
| `build\windows\x64\runner\Release\` | The built app |
| `%APPDATA%\com.pohboonpin\video_downloader\bin\` | yt-dlp and FFmpeg (~275 MB) |
| `%APPDATA%\com.pohboonpin\video_downloader\temp\` | Per-task partial downloads |
| `%APPDATA%\com.pohboonpin\video_downloader\sessions\` | Cookie jars sent by the extension, one per site |
| `%APPDATA%\com.pohboonpin\video_downloader\shared_preferences.json` | Saved settings |
| `%APPDATA%\com.pohboonpin\video_downloader\queue.json` | The saved queue |
| `%USERPROFILE%\Downloads\` | Default output folder (changeable in Settings) |

To reset the app to a clean first-run state, delete the
`%APPDATA%\com.pohboonpin\video_downloader` folder. Note that this also removes the ~275 MB
of tools, so they will be downloaded again.

The `temp\` folder holds partial downloads and is emptied when a task completes, is
cancelled, or is removed. **Paused and failed tasks keep theirs on purpose** — that is the
data a resume continues from. Removing a task from the list is what discards it.

The `sessions\` folder holds cookies, which are credentials. It sits inside the app's
per-user directory rather than anywhere shared, but it is worth knowing it exists before
copying that folder about. Deleting it costs nothing permanent — the extension rewrites a
jar on the next send.

A scratch directory can also be orphaned if the app is force-killed. Nothing sweeps them at
startup, so it is worth an occasional look if disk space matters. Deleting `queue.json`
clears the saved queue without touching finished downloads.
