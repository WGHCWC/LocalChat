# LocalChat

LocalChat is a LAN chat and file transfer app for nearby devices. It is built from the LocalSend codebase and keeps LocalSend's local-network discovery, HTTPS transfer, and cross-platform foundation while adapting the product for chatroom-oriented local communication.

## Origin

LocalChat is based on [LocalSend](https://github.com/localsend/localsend). The original LocalSend project is a free, open-source local-network file sharing app. This repository keeps the upstream foundation and applies LocalChat-specific changes for LAN chat, message synchronization, download behavior, and platform packaging.

## Features

- Discover nearby devices on the local network without an external server.
- Send files, folders, text, and media between desktop and mobile devices.
- Use LAN chatroom messaging with message synchronization across online devices.
- Download pending file messages from the chat view.
- Open links from chat messages in the system browser.
- Preview images on mobile and desktop.
- Build Android, macOS, Windows, Linux, and iOS targets from the Flutter app.

## Repository Layout

- `app/` - Flutter client, native platform runners, Rust bridge, and app assets.
- `common/` - Shared protocol and utility code used by app-side tooling.
- `cli/` - Command-line tooling inherited from the LocalSend project.
- `server/` - Signaling server code for WebRTC-related flows.
- `readme_i18n/` - Short localized README entry points that refer back to this current document.

## Build

Run commands from the `app` directory unless stated otherwise.

```bash
flutter pub get
flutter run
```

Android APK:

```bash
flutter build apk --release
```

macOS:

```bash
flutter build macos --release
```

Windows:

```bash
flutter build windows --release
```

Linux:

```bash
flutter build linux --release
```

## Distribution Notes

This fork has its own release artifacts. LocalSend package-manager links and app-store entries belong to upstream LocalSend and should not be treated as LocalChat distribution channels.

For macOS builds without an Apple Developer account, packages can be ad-hoc signed and distributed as DMG files, but they are not notarized and macOS Gatekeeper may show a warning on first launch.

## License

LocalChat is open-source under the Apache License 2.0, the same license used by upstream LocalSend. See [LICENSE](LICENSE) for the full license text.

LocalChat is derived from LocalSend and keeps the upstream license and notices in this repository. Retain the Apache License 2.0 terms, copyright notices, and platform-specific notices when redistributing source code or binaries.
