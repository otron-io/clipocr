# Changelog

## 1.0.0 — 2026-10-04

First public release.

- Global **⌘⇧6** shortcut and native macOS region selection.
- On-device Apple Vision OCR, with recognized text copied automatically to the clipboard.
- Native menu-bar UI, success/error indicators, and optional launch at login.
- Accurate text recognition without spelling correction; approximate indentation and paragraph spacing.
- Cancellation, bounded capture timeouts, and private temporary-file cleanup.
- Original burgundy/charcoal app icon with ivory and copper accents.
- Universal Apple Silicon + Intel app targeting macOS 13 Ventura and later.
- DMG and ZIP downloads with SHA-256 checksums.

### Release notes

This release is ad-hoc signed, **not Apple-notarized**. Follow the README's first-open/Gatekeeper instructions. Screen Recording permission is required for region capture; Accessibility permission is not.

Local automated testing was performed on Apple Silicon with macOS 26. Both architectures cross-compile with a macOS 13 deployment target; this does not imply every macOS version and Intel model has been runtime-tested. CI results are available in the repository's Actions tab.
