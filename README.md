<p align="center">
  <img src="docs/icon.png" width="128" alt="Twenty app icon">
</p>

<h1 align="center">Twenty</h1>

<p align="center">A tiny macOS menu bar app for the 20-20-20 rule.<br>
Every 20 minutes, look at something 20 feet away for 20 seconds.</p>

<p align="center">
  <a href="https://github.com/JosTheDude/twenty/releases/latest">Download</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="#deploying-to-a-fleet">Deploying to a fleet</a>
</p>

---

## Features

- **Gentle full-screen breaks.** A blurred overlay covers every display with a countdown ring. Press <kbd>Esc</kbd> to skip.
- **Heads-up before a break.** A small pill appears under the menu bar shortly before a break. It never takes focus or blocks clicks, and plays a soft sound and posts a notification so you notice it.
- **Holds breaks during calls.** If your camera or microphone is in use, the break waits until you're done. No permissions needed: Twenty only checks whether a device is busy and never reads audio or video.
- **Streaks.** Each break you finish adds one to your streak. Skipping a break resets it.
- **Smart reset.** No breaks while your screen is off or nobody has touched the keyboard or mouse all interval, so streaks only count real breaks. After your screen wakes, the timer starts a fresh interval.
- **Lightweight.** No dependencies, no Dock icon, no network access. It uses one-shot timers, so it does nothing between breaks.
- **Manageable.** Every setting can be set or locked with a configuration profile.

## Install

1. Download `Twenty-<version>.zip` from the [latest release](https://github.com/JosTheDude/twenty/releases/latest) and unzip it.
2. Move `Twenty.app` to `/Applications`.
3. Release builds are not notarized, so macOS blocks the first launch. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. Or run:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Twenty.app
   ```

Requires macOS 14 Sonoma or later, on Apple silicon or Intel.

## Settings

Open the menu bar icon and choose **Settings…**

| Setting | Key | Default | Range |
| --- | --- | --- | --- |
| Break every | `workMinutes` | 20 min | Presets or any custom value, at least 1 min |
| Break length | `breakSeconds` | 20 sec | Presets or any custom value, at least 5 sec |
| Heads-up | `warnSeconds` | 60 (1 minute before) | 0 (off) or any seconds |
| Edge glow | `glowSeconds` | 8 | 0 (off) or any seconds |
| Edge glow size | `glowWidth` | 160 | Points: 80 (subtle), 160, 320 (bold) |
| Heads-up sound | `warnSound` | Tink | Any system sound name, or empty for none |
| Chime when a break ends | `chime` | On | |
| Hold breaks during calls | `holdInCalls` | On | |
| While video plays | `whileVideoPlays` | quiet | `break`, `quiet` (countdown pill, no overlay), `hold` |
| Open at login | | Off | |

## Deploying to a fleet

Twenty reads its settings from the `io.github.josthedude.Twenty` preferences domain, so any MDM (Jamf, Kandji, Intune, Mosyle…) can set them with a Custom Settings payload. Managed values take priority over whatever users pick in Settings.

```xml
<key>PayloadType</key><string>io.github.josthedude.Twenty</string>
<key>workMinutes</key><real>30</real>
<key>breakSeconds</key><real>30</real>
<key>holdInCalls</key><true/>
```

To open Twenty at login on managed Macs, use a Login Items payload or a LaunchAgent that runs `/Applications/Twenty.app/Contents/MacOS/Twenty`.

## Building from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/JosTheDude/twenty.git
cd twenty
./scripts/build.sh           # build/Twenty.app and build/Twenty-<version>.zip
./scripts/build.sh install   # also replaces /Applications/Twenty.app
```

The build is a universal binary signed ad hoc. Set `SIGN_IDENTITY` to sign with your own Developer ID certificate.

Any setting can be overridden from the command line, which helps when you don't want to wait 20 minutes:

```sh
build/Twenty.app/Contents/MacOS/Twenty -workMinutes 0.1 -breakSeconds 5 -warnSeconds 3
```

### Project layout

| Path | What's there |
| --- | --- |
| `Sources/Twenty/` | The app: entry point, break scheduling, call detection and views |
| `Resources/` | `Info.plist` and the app icon |
| `scripts/build.sh` | Builds, signs and zips the app |
| `scripts/icon.swift` | Draws the app icon. Run `swift scripts/icon.swift` to regenerate `Resources/AppIcon.icns` |

### Releasing

Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, add an entry to the [changelog](CHANGELOG.md), then push a tag:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

GitHub Actions builds the app and publishes the zip to a new release.

## Security

See [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
