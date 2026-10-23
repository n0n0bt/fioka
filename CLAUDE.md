# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

**Fioka** — a fork of [Maccy](https://github.com/p0deje/Maccy) (MIT), a macOS clipboard manager, published at `github.com/n0n0bt/fioka`. It does not track upstream. The public history starts from a single commit ("Fioka 1.0.0", 2026-10-23); Maccy's history and the fork's development up to then are kept locally only, in the branch `maccy-history` and in `~/Dev/fioka-full-history.bundle`. Both copyright lines in `LICENSE` must stay (MIT).

Its core is a **card bar**: a strip along the bottom of the screen showing clipboard history as horizontal cards, instead of upstream's vertical list popup (still there behind a default, see below). Around it: screen text capture, a screenshot editor, card actions and the drop-wheel converter.

**Naming.** Everything is *Fioka*: the app (bundle ID `com.naumchedev.fioka`, `Fioka.app`), the Xcode project, scheme, targets, folders and Swift module (`@testable import Fioka`). Maccy's name survives only where it means Maccy: the credit in `About`, `LegacyMigration`, and links to Maccy's issues in comments. `README.md` describes Fioka; for inherited behaviour, upstream's README is the reference.

## Commands

```bash
./install.sh              # build Release, sign, install to /Applications, relaunch
./install.sh Debug        # same, Debug configuration
./release.sh              # universal build/release/Fioka-<version>.dmg for GitHub Releases

# tests
xcodebuild test -project Fioka.xcodeproj -scheme Fioka \
  -derivedDataPath ./build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES

# a single test class or method
xcodebuild test ... -only-testing:FiokaTests/ColorImageTests
xcodebuild test ... -only-testing:FiokaTests/HistoryTests/testExample
```

`xcodebuild` needs full Xcode selected (`xcode-select -p` must point into `Xcode.app`, not `CommandLineTools`).

A `.swiftlint.yml` is inherited from upstream but `swiftlint` is not installed locally; lint is not part of the loop here.

**Always install via `./install.sh`, never a bare `xcodebuild` + copy.** See Signing below.

## Architecture

### Layer split

The engine has no UI dependencies — `Clipboard.swift` and `Observables/History.swift` contain zero references to SwiftUI. This is what made the fork's UI rewrite tractable, and it is worth preserving.

| Layer | Where | Role |
|---|---|---|
| Engine | `Fioka/*.swift` | Pasteboard polling, storage, paste-back, hotkey, panel, search, sort |
| State | `Fioka/Observables/` | `@Observable` models the views bind to |
| Views | `Fioka/Views/` | SwiftUI only; reads state, never touches the pasteboard |

Everything hangs off `AppState.shared`, which owns `history`, `navigator`, `popup`, `preview`, and `footer`. Views reach it through `@Environment(AppState.self)`.

### Capture and paste

- **There is no clipboard-change notification on macOS.** `Clipboard.swift` polls `NSPasteboard.changeCount` on a timer. Items are stored with *all* their pasteboard representations (RTF, HTML, PNG, file URLs, plain text) via SwiftData into `~/Library/Application Support/Fioka/Storage.sqlite`.
- **Pasting synthesises ⌘V with `CGEvent`**, which requires Accessibility permission. Without it the event is silently dropped — no error, no feedback. `Accessibility.check()` prompts for it.
- `Defaults[.pasteByDefault]` decides whether the plain (⌘) action is `.copy` or `.paste`; see `HistoryItemAction.init`. This fork sets it `true`.

### The panel

`FloatingPanel` is a non-activating `NSPanel` at `.screenSaver` level, so it draws over other apps without stealing focus — that is why the caret stays in the app you paste into. It closes on `resignKey`.

`FloatingPanel.open(height:)` branches immediately on `Defaults[.useCardLayout]`:

- **Card layout** → `openAsCardBar`: fixed height (`Popup.cardPanelHeight`), screen width minus `Popup.cardBarMargin` on every side, all corners rounded, slide-up + fade entrance. Cards are 232×232 squares.
- **List layout** → upstream's content-driven vertical sizing, driven from `HistoryListView` via `Popup.resize`.

### Brand colours

`Views/Brand.swift` holds Fioka's palette, taken from the icon: pink, violet
and cyan, plus near-black ink. Everything the fork draws uses it (the wheel's
highlight, the selected card's ring, hint cards, the bar's faint wash, the
editor's tint and default backdrop) rather than system blue or one-off
colours. `AccentColor` in the asset catalog is the same violet, so stock
controls follow where macOS lets an app set its accent. `ReadmeShowcaseTests`
re-renders the README images (`docs/`) from the real views; rerun it after a
visual change.

### Card layout

`CardKind` classifies an item as text/code/link/file/image/color purely from the pasteboard representations `HistoryItem` already stores — nothing extra is captured at copy time, so existing history classifies retroactively. It also owns each type's colour and gradient. Classification is memoised on `HistoryItemDecorator.kind` (`@ObservationIgnored`, since it is derived state).

Code detection is deliberately conservative: a strong single signal, or three weak ones. Prose with a stray bracket must stay Text. If you loosen it, keep that property.

`CardDrumView` (default) renders the bar as a revolver: the selected card faces
front, ±3 neighbours sit on a drum (rotated, scaled, faded), only the front card
takes clicks and a click on a side card turns to it; ←/→, drags and scroll-wheel
(local `NSEvent` monitor) spin it. `CardCarouselView`, the flat strip, is behind
`defaults write com.naumchedev.fioka cardDrum -bool false`. Both render
`CardItemView`. The drum has no panel: `DrumGlowView` (a shadow pool
plus a brand-colour glow) replaces `PanelBackdropView`, and `FloatingPanel`
drops its rounded clip and window shadow, so the window is clear. It does not
wrap: it opens on the newest with nothing to its left (`CardDrumView.offset`). Selection and keyboard navigation still go through `NavigationManager`, whose `highlightNext`/`highlightPrevious` are direction-agnostic — left/right arrows are mapped onto them in `KeyChord`, alongside up/down.

### Card actions

Right-click a card, or press ⌘K on the selected one, for quick actions:
convert an image (PNG/JPEG/HEIC/TIFF/PDF, WebP if ImageIO can encode it),
compress, resize, save to Downloads, AirDrop; for file cards, copy path,
reveal in Finder, open in Terminal. `CardActions` builds one action list that
both the SwiftUI context menu and the ⌘K `NSMenu` render.

Outputs are written to `Caches/Conversions` and put on the pasteboard as file
URL plus image data, so they arrive as new cards via the poller.

### Drop wheel

Start dragging files anywhere, tap ⇧ (formats), ⌘ (tools) or ⌃ (actions), and
a radial wheel opens under the cursor; drop on a slice to run it. Results are
written **beside the source file** (never overwriting: `photo 2.png`) and put
on the clipboard. The first dragged file's `FileKind` picks the wheel:

| Kind | ⇧ Formats | ⌘ Tools |
|---|---|---|
| Image | PNG JPEG HEIC WebP TIFF AVIF BMP PDF | Compress, Combine (2+, into one PDF), 50%, 25%, Metadata, Text (OCR), Edit |
| Video | MP4 MOV M4V GIF M4A | Compress (HEVC), 720p, Mute, Frame |
| Audio | M4A WAV AIFF FLAC ALAC | Compress, Mono, Normalize |
| PDF | PNG JPEG (per page) TXT DOCX RTF | Compress, Merge (2+, images may be mixed in), Split, Rotate, Text |
| Document | PDF DOCX DOC RTF ODT HTML TXT | Text |
| Subtitle | SRT VTT TXT | — |
| Zip | Extract | — |

⌃ is the same for everything: AirDrop, Copy, Path, Zip, Terminal.

Engines, all with no UI: `ImageConverter` (ImageIO), `MediaConverter`
(AVFoundation for video; `/usr/bin/afconvert` for audio — **it cannot encode
MP3**, Ogg or WMA, so those are input-only), `DocumentConverter` (PDFKit;
`NSAttributedString` importers for Word/RTF/ODT/HTML, the same as TextEdit;
PDF output by printing an `NSTextView` to a file; `zip`/`ditto`). Shared
pieces — `FileKind`, `ConvertedFile` naming, `ExternalTool` — are in
`FileConversion.swift`. `ConverterTests` runs every converter on real files.

- `DropWheelController` — there is no "drag started" API, so a global
  mouse-down records `NSPasteboard(name: .drag).changeCount` and a timer polls,
  while the button is held, for a change and for a newly pressed modifier.
  Polls `NSEvent.modifierFlags` because flagsChanged events go to the dragging
  app's drag loop, not to monitors. Esc closes the wheel the same way, via
  `CGEventSource.keyState`. Also holds `WheelSegments`, what each wheel offers.
- `ImageConverter` — the ImageIO pipeline shared with `CardActions`. Applies
  EXIF orientation (via the thumbnail API) because metadata is not copied.
- `Observables/DropWheel`, `Views/DropWheelView` — state and drawing.
  `DropWheelTests.testRenderWheels` writes `/tmp/maccy-wheel-*.png`.
- Disable with `defaults write com.naumchedev.fioka dropWheelEnabled -bool false`.

### Screen text capture

⌘⇧2 dims the screen, you drag a region, and the recognised text goes to the
clipboard — where the normal poller picks it up, so it lands in history and
appears in the card bar with no special-casing.

- `RegionSelector` — one borderless overlay panel spanning the union of all
  screens, so a drag can cross displays. Reports AppKit (bottom-left) coords.
- `ScreenTextCapture` — coordinate flip to top-left, then ScreenCaptureKit.
  **The CoreGraphics capture calls are `SCREEN_CAPTURE_OBSOLETE` as of macOS 15
  and return nothing**, which is what most online examples still use. OCR runs
  at `.accurate`, unlike the `.fast` title-generating pass in `HistoryItem`.
- `TextCaptureController` — orchestrates, and is started from `AppDelegate`.

Needs **Screen Recording** permission. ScreenCaptureKit reports a missing grant
as an ordinary capture failure, not a distinct error, so failures are surfaced
with a hint about the permission rather than a precise cause.

### Screenshot editor

⌃⌥⌘4 runs `/usr/sbin/screencapture -i` — the real system selector, so Space
toggles window capture — then opens an editor window. Tools: crop, draw, line,
arrow, box, ellipse, highlight, text, numbered steps, spotlight, pixelate,
blur. Backdrop: gradients, a solid colour, or the screenshot itself blurred;
canvas size Auto/1:1/4:3/16:9/9:16; padding, shadow strength, corner radius.
The drop wheel's image Edit tool opens the same editor on any image. Copy writes a PNG to the pasteboard and the poller takes it from
there, as with text capture.

- `ScreenshotController` — hotkey, subprocess, window lifecycle. Falls back to
  `RegionSelector` + ScreenCaptureKit if `screencapture` cannot run. The editor
  is a non-activating floating `NSPanel` on purpose: when the capture ends,
  `screencapture` is frontmost and macOS refuses to activate this app, so a
  plain `NSWindow` opens silently *behind* every other window.
- `Observables/ScreenshotEditor` — annotations in coordinates of the full,
  uncropped image, so they stay put when padding, crop or canvas size change.
  `CompositionLayout` is the single source of where things land: the visible
  (cropped) rect, the canvas size, and `offset` from image to canvas. The view,
  the hit-testing and the export all go through it.
- `Views/ScreenshotEditorView` — `ScreenshotComposition` is drawn by both the
  editor (scaled) and the export (`ImageRenderer` at the capture's pixel scale),
  so the copy matches the screen exactly.

### Website

`docs/` is the landing page, served by GitHub Pages from `main` → `/docs`. Plain
HTML, CSS and JS, no build step; preview with `python3 -m http.server` inside
`docs/`. Its images come from the app's real views via `ReadmeShowcaseTests`
(into `docs/` and `docs/assets/`).

- **Hero drum** (`drum.js`): the card bar is live, not a picture. Each card is
  rendered on its own by `testRenderDrumCards` (`docs/assets/drum/card-N.png`,
  with 10pt of room for its shadow); the selection ring is CSS, so it follows
  the front card. `drum.js` places them with `CardDrumView`'s numbers
  (spacing, turn, shrink, fade, blur) and GSAP animates one value, `pos`.
  Like the app it never wraps and opens on the newest. It autoplays, and ←/→
  (while focused or hovered), drag with flick, sideways trackpad swipes,
  clicks on side cards and ⇧⌘V (`window.fiokaDrum.toggle`) all drive it.
- **Motion** (`motion.js`): hero copy intro, the banner's tilt, and
  ScrollTrigger reveals of each section. Skipped entirely under
  `prefers-reduced-motion`, as is the drum's autoplay.
- **GSAP** 3.15 and ScrollTrigger are vendored in `docs/vendor/` (free under
  GSAP's standard licence), not loaded from a CDN.
- **Demo desktop** (`desktop.js`): a pretend Mac desktop for the drop wheel.
  Pointer-event dragging, not HTML5 drag and drop, because the browser
  withholds key events during a native drag and the gesture needs real
  ⇧/⌘/⌃ presses. It reuses the wheel's geometry and converts images for real
  in the browser.

Bump the `?v=` on a CSS or JS link when changing it; GitHub Pages caches.

## Things that will bite you

**The app is not sandboxed.** `install.sh` re-signs without entitlements, so
the installed build has never been sandboxed — history lives in
`~/Library/Application Support/Fioka`, not a container — and
`Fioka.entitlements` says so too. Features may read and write files freely.

**The rename moved every per-app location.** A new bundle ID means a new
preferences domain and Application Support folder. `LegacyMigration` copies
both from Maccy's (`org.p0deje.Maccy`, `…/Application Support/Maccy`) on the
first launch where Fioka's are empty, and never touches the originals. It runs
from a stored property declared first in `FiokaApp`, so it precedes the app
delegate and every Defaults or Storage access. **The unit tests run inside the
app**, so a test run on a fresh machine triggers it too — harmless, but copy
the database only while Maccy is not running.

**Signing.** macOS ties Accessibility permission to the code signature. Ad-hoc signatures are derived from the binary, so they change every build and the permission has to be re-granted each time. `install.sh` signs with a stable self-signed certificate (SHA-1 `67B262BB…`, in the login keychain, backed up under `~/Library/Application Support/CopyPaste/signing`) so the designated requirement stays constant:

```
identifier "com.naumchedev.fioka" and certificate leaf = H"67b262bb..."
```

Both scripts sign through `scripts/sign-app.sh`, which signs nested code deepest-first. Xcode leaves embedded frameworks (Sparkle especially) on their original signature, and dyld refuses to load a framework whose Team ID differs from the process — which surfaces as a confusing dyld error, not a signing one. Do not suppress codesign's stderr; a silent failure here produces a bundle that fails to launch for an apparently unrelated reason.

Without that certificate (anyone else's machine) both scripts fall back to ad-hoc; `FIOKA_SIGN_ID` points them at another one. Releases are signed with the same certificate, so a downloaded update keeps its Accessibility grant, but they are **not notarized** (no paid developer account): Gatekeeper rejects them until the user clicks Open Anyway, as the README and website explain. `install.sh` leaves an installed Maccy alone and only warns if it is running.

**Stray build copies steal the launch.** Xcode registers build products with
LaunchServices, so Spotlight or `open -a Fioka` can start
`build/Build/Products/*/Fioka.app` rather than the installed one. Those are
ad-hoc signed, so they are a different code identity and carry no Accessibility
grant: the app launches, the bar opens, and Enter silently fails to paste while
System Settings still shows the toggle on. `install.sh` unregisters them, but
check `ps -Ao pid,comm | grep Fioka` before debugging a "stopped pasting" report.

**New Swift files must be registered in the Xcode project.** The project does *not* use `PBXFileSystemSynchronizedRootGroup`, so a file dropped on disk will not compile. Use the `xcodeproj` gem:

```ruby
require "xcodeproj"
project = Xcodeproj::Project.open("Fioka.xcodeproj")
target  = project.targets.find { |t| t.name == "Fioka" }
group   = project.main_group.find_subpath("Fioka/Views", false)
target.add_file_references([group.new_reference("NewView.swift")])
project.save
```

**The slideout preview controller resizes the window.** `SlideoutController` auto-opens after `Defaults[.previewDelay]` (1500ms) and resizes the panel to fit a preview pane. The card layout never renders that pane, so `togglePreview` and `startAutoOpen` are gated on `useCardLayout`. Removing those guards makes the bar shrink ~1.5s after opening.

**Sparkle updates are disabled on purpose.** `Info.plist` inherited upstream's `SUFeedURL`, which would replace Fioka with stock Maccy and discard every change. The feed is removed, both auto-check keys are false, and the updater is not started. Do not re-enable without pointing it somewhere of your own.

**Full-width layout needs explicit `maxWidth: .infinity`.** The panel window can be full width while the SwiftUI content inside sizes to itself and sits left-aligned — it looks like the panel is narrow when it is not. To diagnose panel geometry, read the real bounds with `CGWindowListCopyWindowInfo` rather than judging from a screenshot.

## Defaults that change behaviour

All in the `preferencesSuite`, declared in `Fioka/Extensions/Defaults.Keys+Names.swift`:

| Key | Fork value | Effect |
|---|---|---|
| `useCardLayout` | `true` | Card bar vs. upstream's vertical list |
| `cardBarFullWidth` | `true` | Full screen width vs. centred `cardWindowWidth` |
| `popupPosition` | `.bottom` | Added case; anchors to the bottom edge |
| `pasteByDefault` | `true` | Enter pastes rather than only copying |
| `captureKeepLineBreaks` | `true` | OCR keeps line breaks vs. joining with spaces |
| `capturePlaySound` | `true` | Sound on capture success/failure |
| `dropWheelEnabled` | `true` | Drag-and-tap conversion wheel |
| `cardDrum` | `true` | Revolver card bar vs. the flat strip |

Override at runtime with e.g. `defaults write com.naumchedev.fioka useCardLayout -bool false`.

## Releasing

Public at `github.com/n0n0bt/fioka`. The local branch `fioka` tracks
`origin/main`, so push with `git push origin fioka:main`. The website deploys
from `main` → `/docs` on every push. 1.0.0 shipped on 2026-10-23.

1. Bump `MARKETING_VERSION` (both configurations) and `CURRENT_PROJECT_VERSION`
   in `Fioka.xcodeproj/project.pbxproj`.
2. `./release.sh` builds `build/release/Fioka-<version>.dmg` and prints its SHA-256.
   It must run on the maintainer's Mac: it signs with the stable certificate,
   so users who update keep their Accessibility grant. An ad-hoc release would
   make every user grant it again.
3. Commit, push, then tag and publish:
   ```bash
   git tag -a vX.Y.Z -m "Fioka X.Y.Z" && git push origin vX.Y.Z
   gh release create vX.Y.Z build/release/Fioka-X.Y.Z.dmg --repo n0n0bt/fioka \
     --title "Fioka X.Y.Z" --notes-file <notes.md>
   ```
   Notes: what changed, the install steps including the one-time **Open
   Anyway** step (not notarized), and the SHA-256. v1.0.0's notes are the template.
4. Check that the download's checksum matches the local file.

The website's "Get it for Mac" and the README link to `releases/latest`, so
they need no change. Never push upstream's version tags (`2.x`, still in the
local repo) or the `maccy-history` branch: push only the new tag, never
`--tags` or `--all`. There is no
auto-update: Sparkle is off (see above), so users update by downloading.

## Taking a fix from Maccy

The public history shares no commits with Maccy's, so `git merge` does not
apply. To take a single upstream fix, fetch it and apply the patch, mapping
upstream's `Maccy/`, `MaccyTests/` and `Maccy.xcodeproj` onto `Fioka/`,
`FiokaTests/` and `Fioka.xcodeproj`:

```bash
git fetch upstream
git format-patch -1 <commit> --stdout | sed 's#Maccy/#Fioka/#g; s#MaccyTests/#FiokaTests/#g' | git apply -3
```

Most fork code is in files upstream does not have (`LegacyMigration`, `CardKind`, `CardActions`, `ImageConverter`, `MediaConverter`, `DocumentConverter`, `FileConversion`, `DropWheelController`, `DropWheel`, `Views/DropWheelView`, `Views/CardItemView`, `Views/CardCarouselView`, `RegionSelector`,
`ScreenTextCapture`, `TextCaptureController`, `ScreenshotController`, `ScreenshotEditor`, `Views/ScreenshotEditorView`). The edits that will conflict are in `ContentView`, `FloatingPanel`, `Popup`, `PopupPosition`, `KeyChord`, `HeaderView`, `SlideoutController`, `HistoryItemDecorator`, `Defaults.Keys+Names`, `About`, `Storage`, the project file (bundle IDs, product name) and every `*.strings` file (the name).
