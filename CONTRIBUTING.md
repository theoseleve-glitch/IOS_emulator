# Contributing to the Windows Swift UI / emulator foundation

Thanks for considering a contribution. This is an experimental Windows-first project; its goal is to create a host runtime, UI layer and development tooling, **not** to claim Apple framework or native iOS app compatibility.

## Before you start

1. Read the [README](README.md) and the current supported-host section.
2. Open or select an issue describing observable behavior. For larger features, discuss design and boundaries before implementation.
3. Work in a branch; keep a pull request focused on a reproducible outcome.
4. Do not submit proprietary Apple SDK code, undistributable binaries or unlicensed assets.

## Development setup (Windows x64)

A supported native Windows Swift toolchain and development dependencies are required; use the bootstrap and environment scripts described in the README:

```powershell
.\scripts\bootstrap-windows.ps1
. .\scripts\env-windows.ps1
swift run EmulatorHost doctor --expected-arch x64
swift run EmulatorHost smoke
swift test
```

Use the native graphical demonstration where applicable:

```powershell
swift run EmulatorHost ui-demo
```

If your change affects the external-app SDK or capability negotiation, demonstrate the behavior using an existing `Examples/*` package and `app validate` / `app run` commands documented in the README.

## What to include in a pull request

- **Problem:** expected vs actual behavior, with a reproducible input or command
- **Change:** concise explanation of runtime/API effects and design trade-offs
- **Validation:** exact commands run and their results; explicitly name untested platforms
- **Compatibility:** affected SDK contracts, platform assumptions and configuration choices
- **Evidence:** relevant trace/log output or screenshots for rendered UI changes

## Areas where reviews are especially valuable

- Focus, keyboard and pointer event handling
- Layout constraints, safe areas and device presets
- Deterministic BLE mock behavior and host capability errors
- FFI / Objective-C bridge lifetime and ABI tests
- Windows ARM64 validation and diagnostics **on actual ARM64 hardware**
- Clearer onboarding of external Swift example packages

## Testing boundaries

A passing mock Bluetooth test is **not** evidence that a WinRT adapter worked on a physical device. A Windows x64 build is **not** evidence that native Windows ARM64 support passed. Keep those distinctions explicit in PRs and documentation.

## License

By contributing, you agree that submitted code can be distributed under the repository's existing [MIT license](LICENSE), and that you have the rights needed to submit it.
