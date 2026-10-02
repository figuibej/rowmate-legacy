# Contributing to RowMate 🚣

Thanks for your interest! All contributions are welcome — from reporting your rower as compatible to adding new features.

## How Can I Contribute?

### 🐛 Report a Bug
Open an [issue](../../issues/new) with:
- Your rower model and BLE module
- OS version / device
- Steps to reproduce the problem
- Console logs if available (BLE debug mode is available in the Device screen)

### ✅ Report Rower Compatibility
If you tested RowMate with a rowing machine not on the list, open an issue with:
- Rower name and model
- BLE module / receiver brand
- Whether it worked correctly or what failed

### 💡 Suggest a Feature
Open an issue describing what you want to add and why it would be useful for the community.

### 🔧 Submit a Pull Request

1. Fork the repo
2. Create a descriptive branch:
   ```bash
   git checkout -b feature/feature-name
   # or
   git checkout -b fix/bug-description
   ```
3. Make your changes. No rowing machine? Try UI changes in simulator mode:
   `flutter run --dart-define=SIMULATOR=true` (see the README). Then run the checks:
   ```bash
   flutter analyze
   flutter test
   ```
4. Commit with a clear message:
   ```bash
   git commit -m "feat: add heart rate zone display"
   ```
5. Push and open a PR against `main`

## Code Style

- We follow `flutter_lints` rules (automatically checked in CI)
- Code in English, UI text and comments can be in whichever language fits
- New features should come with tests when applicable

## Architecture

Before making large changes, check [CLAUDE.md](./CLAUDE.md) which documents the architecture in detail.

## Code of Conduct

Be respectful and constructive. The goal is to build the best possible tool for the rowing community. 🚣
