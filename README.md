# VintageStream Client

Modular Flutter client for VintageStream. Plays the **original** file through libmpv (via media_kit) so the server does not transcode.

## Layout

```
lib/                  App shell (navigation, settings, OTA)
android/              Android project
packages/vs_core/     Models, API, settings, watch progress, GitHub updates
packages/vs_ui/       Shared theme tokens
packages/vs_catalog/  Library / search / show details / network stream UI
packages/vs_player/   In-app player (media_kit / libmpv)
dist/                 Built APK output
scripts/              build_apk.sh · publish_apk.sh
```

Shared packages stay reusable for a future Linux/Windows desktop app.

## Server URL

No built-in default. Set your host in **Settings** (public or LAN). Without a saved server URL the library stays empty; the app-bar **network** icon still opens a direct stream URL (mpv-style).

## How media is fetched

All VintageStream calls use the saved base URL (`https://your-host`). The JSON catalog and metadata go through `http`; posters/thumbnails are loaded as image URLs; video and sidecar subtitles are opened by libmpv (HTTP Range), not downloaded into the app first.

**Typical play path**

1. `GET /api/library` — browse Movies / TV / Marvel
2. Open a title → posters via TMDB URL or `/api/thumbnail`
3. Play → optional `GET /api/metadata` (codecs, sidecar sub list)
4. libmpv opens `GET /stream?id=…&resolution=original` (Range)
5. Sidecar track selected → libmpv loads `GET /api/subtitle-file?id=…&index=…`

**Network stream** skips the library APIs and opens whatever HTTP(S) URL you paste.

### VintageStream server APIs

| Method | Path | Used for |
|---|---|---|
| `GET` | `/api/library` | Full catalog JSON (`movies`, `shows`, `marvel`) |
| `GET` | `/api/metadata?id={id}` | Duration, codecs, play mode, embedded + sidecar subtitle list |
| `GET` | `/api/thumbnail?id={id}` | Fallback poster when TMDB path is missing |
| `GET` | `/api/subtitle-file?id={id}&index={index}` | Raw sidecar subtitle file (`.srt` / `.ass` / …), no FFmpeg |
| `GET` | `/stream?id={id}&resolution=original` | Direct-play video (HTTP Range); libmpv is the client |
| `GET` | `/stream?id={id}&resolution=original&download=true` | Same file as an attachment; opened via external browser / downloader |

Posters: if `posterPath` is an absolute `http(s)` URL (usually TMDB), the image widget loads it directly. Relative paths are resolved against the server root; otherwise `/api/thumbnail?id=…` is used.

Defined in `packages/vs_core/lib/src/urls.dart` (`StreamUrls`). The thin JSON client is `VintageStreamApi` (`fetchLibrary`, `fetchMetadata` only); stream / subtitle / download URLs are passed to the player or `url_launcher`.

### GitHub (in-app updates)

| Method | URL | Used for |
|---|---|---|
| `GET` | `https://api.github.com/repos/{owner}/{repo}/releases/latest` | Latest release tag + assets |
| `GET` | asset `browser_download_url` for `latest.json` (optional) | Override notes / sha256 / mandatory / apk URL |
| `GET` | asset `browser_download_url` for `VintageStream.apk` | APK download (via `ota_update`) |

Default update repo: `s-vintagew/vintagestream-client` (changeable in Settings). Release tag must look like `0.2.0+2` (version name + Android `versionCode`).

### Not called by this client

- HLS / transcode stream modes (`resolution` other than `original`)
- Server-side subtitle burn-in / FFmpeg convert endpoints
- TMDB API directly (metadata and most posters already come from the VintageStream server)

## Features (player)

- Seek scrub, double-tap skip, speed
- Audio / subtitle track pick + subtitle size & vertical position
- Fit screen / Crop / Stretch; controls lock
- Optional brightness / volume edge swipes (Android, off by default)
- Resume position per title / network URL

## Build & release

**Production:** push/merge to `main` runs `.github/workflows/release-android.yml`. It reads `version:` from `pubspec.yaml` (e.g. `0.2.0+2`), builds a **signed** APK, and publishes a GitHub Release with that tag plus `VintageStream.apk` and `latest.json`.

Bump `version:` in `pubspec.yaml` before merging when you want a new OTA build. Required repo secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`. See `../VINTAGESTREAM_CLIENT_RELEASE.md`.

**Local** (path with spaces → rsync to `~/development/vintagestream-client`):

```bash
./scripts/build_apk.sh
# → dist/VintageStream.apk
# Needs android/key.properties + upload keystore for a release-signed APK
```

Manual GitHub publish (emergency):

```bash
./scripts/publish_apk.sh
```

## Package name

Dart package: `vintagestream_client`. Android `applicationId` stays `org.vintagewizard.vintagestream_mobile` so existing installs keep receiving OTA updates.
