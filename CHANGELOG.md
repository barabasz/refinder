# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.1] - 2025-12-01

### Added

- Initial release of ReFinder
- Menu bar application with system tray icon
- Block mode: clicking Finder icon in Dock does nothing
- Redirect mode: launch alternative file manager instead of Finder
- Settings persistence using UserDefaults
- Accessibility permission check and prompt
- Support for macOS 12.0 (Monterey) and later

### Technical

- CGEvent Tap for intercepting mouse clicks
- AXUIElement (Accessibility API) for Dock icon identification
- Non-sandboxed app configuration for Accessibility API access
- LSUIElement for menu bar only mode (no Dock icon)

[Unreleased]: https://github.com/andrzej/ReFinder/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/andrzej/ReFinder/releases/tag/v0.0.1
