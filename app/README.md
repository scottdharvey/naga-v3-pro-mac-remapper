# Naga Remapper app source

SwiftUI app (macOS 13+) built with Swift Package Manager. See the main [README](../README.md) for install steps.

- `Sources/NagaKit/RazerDevice.swift`: HID transport. Sends 90-byte feature reports and reads/writes button mappings.
- `Sources/NagaKit/Model.swift`: button catalog, action encoding/decoding, factory defaults, config file format.
- `Sources/NagaRemapper/`: the app (model and SwiftUI views).
- `build-app.sh`: builds the release binary and wraps it in an ad-hoc-signed `.app` bundle.
