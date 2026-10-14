# Resource usage

Changes made on 2026-10-13:

- Pointer hit testing follows AppKit events, coalesces queued mouse updates, and caches the notch path. A one-second fallback handles missing pointer events, comparing coordinates before doing any work. The old 150 ms redraw/state-update loop is gone.
- The drag-completion watchdog starts only after a drag begins and stops when the drag finishes. There is no idle drag timer.
- Clipboard capture retains its 0.5-second responsiveness while enabled. Pausing history invalidates that timer, and resuming skips content copied during the pause. Retention runs separately about once per minute with a 15-second tolerance.
- No-op retention does not save, fetch, or publish the clipboard collection. Explicit saves replace redundant SwiftData autosaving.
- Clipboard hashes stream fields through SHA-256 instead of allocating a combined payload-sized buffer. Existing hashes remain compatible.
- Image paste preserves the captured PNG/TIFF bytes. Image drops keep their encoded format instead of decoding and expanding everything into TIFF.
- File tiles reuse resolved bookmarks and icons across view updates. Identical hover states no longer restart layer animations.
- Closing Settings releases its window and hosted view. The existing thumbnail cache remains bounded to 100 thumbnails / 4 MB.

## Measurement

Use `scripts/profile-idle.sh` with the panel collapsed. It samples the running process six times, two seconds apart. Ignore the first CPU reading because it has no sampling interval. CPU is a percentage of one core; a displayed 0.0% is rounded, not a claim of zero work. `top` memory is its process footprint estimate, not virtual memory or a heap-only total.

Both before and after observations used local Debug builds on the same Mac with the existing history. These were short observational samples while other apps were running, not a controlled benchmark. Before optimization, the three usable idle CPU readings were 0.5%, 0.5%, and 3.7%, and a separate `sample` report showed a 32.2 MB physical footprint. Steady memory was broadly unchanged after the changes; the memory optimizations target temporary copying/decoding allocations, which this idle sample does not measure.

The final running build was sampled again after continued use: seven interval CPU readings were 0.0%, 0.0%, 0.0%, 3.5%, 1.5%, 1.9%, and 2.4%, with a footprint of about 39 MB. These observations do not establish a consistent CPU percentage improvement or lower steady RAM; interaction, captured content, and cache warm-up were not controlled. The verified improvements are fewer idle timers, fewer redundant state/database updates, and avoided payload-sized image allocations.

26 tests pass, including paused timer lifecycle, skip-on-resume behavior, no-op retention notifications, hash compatibility, encoded image copying, hover cancellation, and the existing clipboard/file regressions. The final development app's code signature verifies and the development DMG was rebuilt.

Implementation references: [Apple event monitoring](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html), [timer lifetime and tolerance](https://developer.apple.com/documentation/foundation/timer).
