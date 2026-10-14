# Verification and release checklist

## Automated

Run `scripts/test.sh`. Store tests cover:

- Concealed/transient/auto-generated pasteboard filtering and actual capture suppression.
- Clipboard recording disabled on first run; app exclusion whitespace.
- Content deduplication retaining pin status and updating source metadata.
- Age/count pruning, pin exemption, clearing unpinned entries.
- Clipboard writes suppressed from the app's own capture loop; RTF-sensitive hashing.
- Shelf managed-copy persistence across store reloads; removing entries keeps files.

## Local checks completed

- Debug build and 29 XCTest tests passed with Xcode 27.
- Running app: Settings, compact shelf empty state, and clipboard history layout inspected.
- Panel expanded through pointer interaction, and the Clipboard tab switched correctly.
- Shell syntax checked for build, test, and release scripts.
- Global shortcut behavior from another app and keyboard search interaction still need manual verification; automated UI input did not reliably exercise the system-wide shortcut.

## Manual release matrix

The panel is intentionally visible over full-screen apps (`fullScreenAuxiliary`). It joins Spaces and is stationary; it does not provide a separate Mission Control surface. Verify actual behavior on target hardware.

- [ ] Hover: 100 ms entry, 300 ms exit; crossing the menu bar quickly does not leave the shelf open.
- [ ] Transparent area passes clicks to the underlying app; concave corners don't swallow clicks.
- [ ] Global file drag reveals peek; dropping into the shelf performs exactly one action.
- [ ] Cancelled drag or Escape clears peek; repeated drags of the same file reveal it again.
- [ ] Drag selected shelf files to Finder/Mail; cancellation retains shelf entries when remove-after-drag is enabled.
- [ ] Move/rename original files, relaunch, verify bookmark resolution; delete an original and check unavailable state.
- [ ] Clipboard shortcut opens Clipboard and focuses search from another app; ↑/↓ and Return work, including an empty result set.
- [ ] Clipboard recording OFF captures nothing; excluded and concealed data is skipped; test native Tahoe pasteboard permission prompts.
- [ ] Test text/RTF, image, URL, and multiple-file copies; verify persistence after relaunch.
- [ ] Accessibility denied: copy message appears. Granted: prior app reactivates and receives one paste; no paste if focus moves elsewhere.
- [ ] Clamshell external-only fallback; unplug/replug; lid reopening and scaled modes rebuild cleanly.
- [ ] Multiple Spaces, full-screen apps with hidden menu bar, Stage Manager, Mission Control.
- [ ] Energy impact in Activity Monitor while idle, copying large images, and dragging large directories.
- [ ] Developer ID archive, notarization acceptance, stapling, clean-machine Gatekeeper check, signed Sparkle update.

Do not mark hardware/permission checks complete based on a successful build or unit tests.

- [ ] Reduce Motion disables expansion motion; rapid enter/exit reverses without bouncing or text reflow.
- [ ] Click below the compact shelf reaches the underlying app despite the larger fixed panel frame.

- [ ] Drag a saved file by its icon and its filename to Finder; test multi-selection and cancellation.
- [ ] Hover highlights each file tile and shows an open-hand cursor; the grid stays fixed during drag-out.
- [ ] No AirDrop controls or sharing actions remain.

Latest regression checks: repeated temporary-file imports across reloads, source aliases, repeated raw drops, legacy raw-drop duplicate migration, multi-file Finder pasteboard format, and full-tile first-mouse handling. Finder drag-out visual verification was interrupted by the UI automation connection closing; it remains a manual check.

- [ ] Clipboard search, clear-search, pinned filter, hover actions, and empty states remain readable in the compact panel.
- [ ] Both tab menus show clear options; Cancel retains entries; confirm clears only the selected scope. Automated store tests cover preservation of saved files and the current clipboard.

Clipboard auto-close regression tests confirm that focusing search does not hold the panel open and returning the pointer cancels delayed dismissal.

Verified in the running app: optimized clipboard rows and thumbnail rendering, options button placement, and collapse after moving the pointer outside the clipboard while search was focused.

Performance regression tests cover stopping capture polling when paused, resuming without capturing paused content, skipping no-op retention refreshes, preserving streaming hash identity, and lossless encoded image copies.

VS Code compatibility tests cover multi-file capture, Unicode/escaped filenames, Finder and VS Code clipboard round trips, duplicate filtering, remote-resource rejection, malformed-data text fallback, and privacy markers. Format reference: [VS Code native clipboard service](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/services/clipboard/electron-browser/clipboardService.ts). Live Explorer-to-Finder interaction remains a manual check.
