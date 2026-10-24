# Changelog

All notable changes to Twenty are documented here. This project uses [Semantic Versioning](https://semver.org).

## [1.3.0] - 2026-10-23

- While a video plays, breaks become a quiet countdown pill under the menu bar; Settings can hold the break instead, or keep the full overlay
- `scripts/build.sh install` relaunches the app
- Timers no longer drift under App Nap, so the heads-up and edge glow land on time
- Settings regrouped into Breaks, Heads-up and Edge glow; every timing picker has a Custom… entry; version shown under About

## [1.2.0] - 2026-10-23

- Screen edges pulse before a break, 8 seconds by default; lead time and size are configurable in Settings
- Faster, springier break overlay entrance

## [1.1.0] - 2026-10-23

- Sound when the heads-up pill appears, configurable in Settings
- Notification alongside the heads-up pill
- Breaks no longer run, or count toward your streak, while the screen is off or nobody has touched the keyboard or mouse all interval
- Settings locked by a configuration profile are greyed out in Settings

## [1.0.0] - 2026-10-23

First public release.

- Full-screen break overlay on every display, with a countdown ring and <kbd>Esc</kbd> to skip
- Heads-up pill before each break
- Holds breaks while the camera or microphone is in use
- Streaks of finished breaks
- Fresh interval after the screen wakes from sleep
- Settings manageable through configuration profiles
- Universal binary for Apple silicon and Intel

[1.1.0]: https://github.com/JosTheDude/twenty/releases/tag/v1.1.0
[1.0.0]: https://github.com/JosTheDude/twenty/releases/tag/v1.0.0
