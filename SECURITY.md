# Security

## What Twenty accesses

- **Camera and microphone:** only whether a device is busy, through CoreMediaIO and CoreAudio. Twenty never opens a device or reads audio or video, so macOS never asks for permission.
- **Network:** none.
- **Data:** settings and streak counts in its own preferences domain, `io.github.josthedude.Twenty`. Nothing leaves the Mac.

## Reporting a vulnerability

Please report vulnerabilities privately through [GitHub security advisories](https://github.com/JosTheDude/twenty/security/advisories/new), not public issues. Only the latest release gets security fixes.
