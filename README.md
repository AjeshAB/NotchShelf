# NotchShelf

A native macOS 26+ shelf and clipboard history tucked into the MacBook notch. Built with Swift, AppKit, SwiftUI, SwiftData, KeyboardShortcuts, and Sparkle.

## Run

Requires Xcode with a macOS 26+ SDK and XcodeGen (`brew install xcodegen`).

```sh
./scripts/build.sh
open build/Build/Products/Debug/NotchShelf.app
```

Or open `NotchShelf.xcodeproj`, choose the NotchShelf scheme and your signing team, then Run. `project.yml` is the source of truth for the generated project. The app has a menu-bar icon and no Dock icon.

## Use

- Hover at the notch to open the shelf. On an external-only setup, a black pill appears at the top of the primary display.
- Drop files, images, or text onto the shelf. Adding items is drag-and-drop only.
- Drag anywhere on a file tile to move a copy into another app. ⌘-click items to select multiple files. Removal after a successful drag is optional.
- Select **Clipboard** above the shelf or press **⌥⌘V** to open clipboard search; use arrow keys and Return. Change the shortcut in Settings.
- Use the **…** menu beside the tabs to clear Files, clear unpinned clipboard history, or clear all history including pins. Each action asks for confirmation. Clearing Files keeps originals and managed copies; clearing history leaves the system clipboard intact.
- Clipboard recording is **off by default**. Enable it in Settings. Text/RTF, images, file URLs, and web links are supported. Local files copied in VS Code Explorer are captured as files; copying a file entry from history supports both Finder and VS Code. Remote SSH/container resources are not imported as local files. Pin items to retain them beyond ordinary history limits.
- Grant Accessibility using Settings only if you want automatic paste into the previous app. Otherwise the selected item is copied for manual ⌘V.
- Settings and clipboard history are available from the menu-bar icon. Launch at login is opt-in.

## Data and privacy

Shelf metadata and the SwiftData clipboard database live in `~/Library/Application Support/NotchShelf/`. Original files are referenced using bookmarks; temporary files and raw drops are copied into `Shelf/`. Removing a shelf entry never deletes its original file or managed copy, so an in-flight drag or copied URL remains usable. Use **Show saved files** in Settings to manage those retained copies.

Clipboard polling runs every 0.5 seconds while history is enabled, with timer tolerance; it stops while history is paused. Concealed, transient, and auto-generated pasteboard markers are ignored. App exclusions use bundle identifiers of the frontmost app at capture time; macOS does not provide reliable originating-app metadata for every clipboard write. Password-manager defaults are supplied, and users can add more exclusions. Images over 25 MB and text over 2 MB are skipped. Rich text is limited to 5 MB. Pinned history is exempt from age/count limits. Retention runs on startup, inserts, settings changes, and about once per minute while running.

The app is not sandboxed. History is local, without cloud sync or analytics. OS clipboard and folder-access prompts may appear. Privacy markers depend on the source app; exclusion lists are not a guarantee that arbitrary copied secrets will be recognized.

## Implementation

- `Window/`: one fixed-size nonactivating panel per built-in display, or one fallback panel on the primary display; screen rebuild notifications; animated black notch silhouette; tracking areas and pointer monitoring for click-through.
- `Models/` and `Services/`: bookmark shelf persistence, SwiftData history with external binary storage, drag detection and source-aware duplicate prevention.
- `Views/`: compact shelf grid with hover feedback, larger glass navigation buttons, multi-file AppKit drag source, clipboard search, pinning, keyboard selection, native settings.
- `App/`: service lifecycle, customizable global shortcut, previous-app restoration, Accessibility paste, menu-bar entry, opt-in launch at login, configured Sparkle updater.

Drag-out uses normal file URLs.

## Motion and simplicity

The shelf has no branding header, toolbar, status footer, battery HUD, file picker, or quick actions. Its 480 × 240 pt expanded surface keeps attention on files; larger glass Files / Clipboard buttons gives direct access to history and search. The panel's maximum frame stays fixed, while a non-bouncy SwiftUI spring animates the black silhouette. Content lays out at its destination size to avoid reflow during the reveal. Reduce Motion disables the expanding spring and file-hover fade. Repeated drops of the same source file or raw content reuse the existing shelf entry; distinct source files remain separate.

This follows Apple's emphasis on continuous, interruptible motion in [Animate with springs](https://developer.apple.com/videos/play/wwdc2023/10158/) and the control/content hierarchy in [Materials](https://developer.apple.com/design/human-interface-guidelines/materials).

## Verification

```sh
./scripts/test.sh
```

The tests use an in-memory clipboard database, isolated pasteboards, and temporary shelf directories. See [docs/QA.md](docs/QA.md) for automated coverage and the hardware/permissions test matrix.

## Distribution

Development builds are locally ad-hoc signed. They are not notarized releases. Run `./scripts/package-local.sh` to create `build/NotchShelf-development.dmg` with an Applications shortcut.

`./scripts/release.sh` archives, signs, notarizes, staples, and builds a DMG with an Applications shortcut. Provide `TEAM_ID`, `SIGN_IDENTITY`, `NOTARY_PROFILE`, `SPARKLE_FEED_URL`, and `SPARKLE_PUBLIC_KEY`. Store notarization credentials in the keychain using `xcrun notarytool store-credentials` rather than committing secrets.

Sparkle only starts when a real feed URL and public EdDSA key are present in the app's Info.plist. The release script injects them before the final signature. Use Sparkle's `generate_keys` and `generate_appcast` tools to provision update signing and generate the signed appcast; upload the appcast and release artifact to your HTTPS hosting. Neither signing credentials nor hosting are included.

## Later

AirPods connection notifications, calendar events, Pomodoro, and Now Playing are outside this first implementation. Full-screen/Spaces, Stage Manager, clamshell changes, scaled display modes, and real permission dialogs still need the manual release checks in `docs/QA.md`.

References: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), [SwiftUI Liquid Glass](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)), [Sparkle](https://sparkle-project.org/).

Clipboard UI uses compact rows with hover actions, search clearing, a pinned-only filter, and cached downsampled image previews. Double-click an item or press Return to copy/paste.

For resource measurements and implementation details, see [docs/Performance.md](docs/Performance.md). Run `scripts/profile-idle.sh` to sample idle CPU and memory.
