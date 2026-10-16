<!-- portfolio-clarity-intro-2026 -->
> **Scope clarification:** This project is a **Windows-first Swift runtime and UI framework experiment**, not a working iOS simulator. It currently does **not** execute App Store applications, iOS binaries or Apple's UIKit/SwiftUI frameworks. The goal is to build and test the foundations incrementally, with reproducible CLI and Win32 demonstrations.
>
> **Start here:** On a supported Windows x64 host, follow [Windows Bootstrap](#windows-bootstrap), then run `swift run EmulatorHost doctor --expected-arch x64`, `swift run EmulatorHost smoke`, and `swift test`. To explore an interactive graphical window, use `swift run EmulatorHost ui-demo`.
>
> **Open-source contributions:** The code is MIT-licensed. See [CONTRIBUTING.md](./CONTRIBUTING.md) for reproducible issues, testing expectations and safe contribution boundaries.
<!-- end-portfolio-clarity-intro-2026 -->

# iPhone Emulator Foundation

The repository now has eight completed implementation blocks, plus an active hardening track:

- Block 1: native Windows Swift runtime foundation, FFI bridge, and Objective-C experiment
- Block 2: a Windows-only SwiftUI-inspired UI engine with a retained render tree, layout pipeline, terminal smoke renderer, and native Win32 graphical backend
- Block 3: generic local-package app onboarding through `EmulatorAppSDK`, asset catalogs, and generated runner workspaces
- Block 4: a host services SDK and capability-validation layer for storage, logging, clock, network, and clipboard access
- Block 5: a generic GATT-first Bluetooth service adapter with mock fallback, Win32 invalidation hooks, and an external BLE example app
- Block 6: device presets, safe-area-aware rendering, keyboard focus routing, lifecycle simulation, and a device showcase app
- Block 7: CLI-first devtools for inspection, trace capture, and runtime compatibility reporting for external apps
- Block 8: single-line text input, pointer phases, synthetic drag/swipe/long-press/pinch/rotate gesture routing, and an external input playground app

The hardening track now also includes:

- architecture-aware Windows bootstrap and `doctor --expected-arch <x64|arm64>`
- a native `validate-windows-arm64.ps1` acceptance script for real Windows ARM64 hardware
- expanded Objective-C experiment backend selection and compatibility validation through `objc-check --backend <auto|embedded|libobjc2> --suite <basic|compat>`

It still does not emulate iOS yet. The current scope focuses on:

- bootstrapping a Windows Swift toolchain and supporting native build tools
- defining shared runtime contracts for boot, run, shutdown, allocation, threading, and library loading
- providing both a legacy POSIX runtime and a Windows-first `RuntimeWin32` foundation
- loading compiled-in app modules through a typed Swift registry
- validating a plain C ABI bridge from Swift for callbacks, strings, and raw bytes
- validating an experimental Objective-C bridge through a stable C ABI and a small sample runtime
- providing a SwiftUI-inspired internal UI DSL with stacks, text, buttons, gauges, lists, and navigation
- exposing a stable developer-facing `EmulatorAppSDK` for third-party example apps
- loading PNG images, named colors, and localized strings from SwiftPM resources
- onboarding external local Swift packages without editing this repo's `Package.swift`
- letting apps declare required host capabilities before launch
- validating service availability per renderer before external app runs
- providing typed host services for storage, logging, clocks, networking, and clipboard access
- providing a generic Bluetooth service surface with `auto`, `mock`, and `winrt` backend modes
- letting background services request Win32 redraws through a thread-safe invalidation bridge
- resolving emulator-defined device presets, orientation, viewport scale, and safe area insets before each document build
- letting apps opt into render-environment-aware document building plus input and lifecycle event handling
- routing keyboard focus with Tab, Shift+Tab, arrows, Enter, Space, and Escape across actionable UI regions
- routing single-line editable text input, caret movement, submit, pointer phases, and synthetic gesture events through optional controller protocols
- simulating background/resume and one-shot device rotation during app runs
- collecting runtime diagnostics markers, redraw events, focus changes, lifecycle events, and renderer frames
- exporting CLI inspection snapshots, ordered traces, and compatibility reports for local external packages
- producing a shared render pipeline of declarative tree -> measured layout tree -> backend-agnostic draw commands
- rendering the UI both in a terminal smoke preview and in a native Win32 window through Direct2D + DirectWrite

## Supported Host

- Windows 10/11 `x64`
- Swift 6.3 for Windows
- Visual Studio Build Tools with Windows 11 SDK 22000 or newer, MSVC x64 tools, and MSVC ARM64 tools
- LLVM / Clang
- CMake
- Python 3.10
- MSYS2
- NASM

WSL remains in the repo only as a legacy comparison path. It is no longer the primary bootstrap or acceptance target.

Windows ARM64 is now an explicit native validation target through `scripts/validate-windows-arm64.ps1`, but that acceptance path must be run on real ARM64 hardware. It is not considered closed by cross-compiling from this `x64` machine.

## Windows Bootstrap

From the repository root in PowerShell:

```powershell
.\scripts\bootstrap-windows.ps1
. .\scripts\env-windows.ps1
```

The bootstrap script validates or installs the Windows toolchain stack with `winget`, checks Developer Mode, detects the current host architecture, and verifies the core executables needed for the native host.

For native ARM64 hardware, the prepared acceptance script is:

```powershell
.\scripts\validate-windows-arm64.ps1
```

## Commands

From a PowerShell session after dot-sourcing `.\scripts\env-windows.ps1`:

```powershell
swift run EmulatorHost doctor --expected-arch x64
swift run EmulatorHost ffi-check
swift run EmulatorHost objc-check --suite basic --backend embedded
swift run EmulatorHost objc-check --suite compat --backend libobjc2
swift run EmulatorHost smoke
swift run EmulatorHost ui-demo
swift run EmulatorHost ui-demo --device-preset tablet --orientation landscape --autoclose-ms 2000 --background-after-ms 500 --resume-after-ms 900 --rotate-after-ms 1200
swift run EmulatorHost bluetooth-check --backend mock
swift run EmulatorHost app validate --package-path Examples/StarterTelemetryApp
swift run EmulatorHost app run --package-path Examples/StarterTelemetryApp --renderer text
swift run EmulatorHost app run --package-path Examples/StarterTelemetryApp --renderer win32 --autoclose-ms 1500
swift run EmulatorHost app inspect --package-path Examples/StarterTelemetryApp --renderer win32 --format json
swift run EmulatorHost app validate --package-path Examples/BluetoothTelemetryApp --bluetooth-backend mock
swift run EmulatorHost app run --package-path Examples/BluetoothTelemetryApp --renderer text --bluetooth-backend mock
swift run EmulatorHost app run --package-path Examples/BluetoothTelemetryApp --renderer win32 --autoclose-ms 2000 --bluetooth-backend mock
swift run EmulatorHost app validate --package-path Examples/DeviceShowcaseApp
swift run EmulatorHost app run --package-path Examples/DeviceShowcaseApp --renderer text --device-preset tablet --orientation landscape
swift run EmulatorHost app run --package-path Examples/DeviceShowcaseApp --renderer win32 --autoclose-ms 2000 --background-after-ms 500 --resume-after-ms 900 --rotate-after-ms 1200
swift run EmulatorHost app validate --package-path Examples/InputPlaygroundApp
swift run EmulatorHost app run --package-path Examples/InputPlaygroundApp --renderer text
swift run EmulatorHost app run --package-path Examples/InputPlaygroundApp --renderer win32 --autoclose-ms 2000
swift run EmulatorHost app trace --package-path Examples/DeviceShowcaseApp --renderer win32 --autoclose-ms 1500 --background-after-ms 500 --resume-after-ms 900 --rotate-after-ms 1200
swift run EmulatorHost app compat-check --package-path Examples/BluetoothTelemetryApp --bluetooth-backend mock
swift test
```

- `doctor [--expected-arch <x64|arm64>]` validates the native Windows host, current architecture, Developer Mode, package shape, toolchain paths, and a build-ready `EmulatorHost` product without running the full test suite.
- `ffi-check` validates the plain C callback, string, and byte round-trip bridge.
- `objc-check --suite basic --backend embedded` validates the embedded Objective-C experiment bridge and sample class/message-send flow.
- `objc-check --suite compat --backend libobjc2` validates the richer compatibility suite and requires the real `libobjc2` backend on Windows.
- `smoke` boots the runtime, renders the terminal preview, runs the FFI check, and shuts down cleanly.
- `ui-demo` opens the native Win32 demo window, renders the retained SwiftUI-inspired scene, and supports pointer hit-testing for buttons and list rows.
- `ui-demo` also accepts `--device-preset`, `--orientation`, `--autoclose-ms`, `--background-after-ms`, `--resume-after-ms`, and `--rotate-after-ms` so the demo can exercise block-6 device and lifecycle simulation.
- `ui-demo` automated validation now also proves text entry, submit, pointer drag, long press, synthetic pinch, and synthetic rotate in the internal input lab route.
- `bluetooth-check [--backend <auto|mock|winrt>]` validates backend selection, scan/connect/discover/read/write/notify flow. The mock backend is the deterministic automated acceptance path; the WinRT backend is the live manual path.
- `app validate --package-path <path>` generates a cached runner workspace under `.emulator-cache/runners`, compiles the external package against `EmulatorAppSDK`, instantiates its registration type, and renders one document as a structural validation pass.
- `app validate --package-path <path>` also prints a compact capability summary for each supported renderer and fails if no supported renderer can satisfy the app's required capabilities.
- `app run --package-path <path> --renderer text` renders an external package in the terminal host.
- `app run --package-path <path> --renderer win32 --autoclose-ms <n>` opens the external package in the native Win32 window host.
- `app inspect --package-path <path> --renderer <text|win32> [--format <text|json>]` produces a one-shot render snapshot with environment, tree, interactions, focus, counts, and clipping/resource warnings.
- `app trace --package-path <path> --renderer <text|win32> [--format <text|json>]` runs the app and emits ordered lifecycle, input, action, redraw, frame, Bluetooth, and app-defined diagnostics markers.
- `app compat-check --package-path <path> [--renderer <text|win32>] [--format <text|json>]` reports host-verifiable compatibility issues such as degraded capabilities, unsupported renderers, locale fallback, and layout/resource warnings.
- External app commands also accept `--bluetooth-backend <auto|mock|winrt>` so apps can force mock Bluetooth for deterministic runs or require the live WinRT adapter.
- External app runs also accept `--device-preset`, `--orientation`, `--background-after-ms`, `--resume-after-ms`, and `--rotate-after-ms` so apps can validate safe-area-aware layouts and lifecycle behavior without editing app code.

For scripted validation of the window loop without leaving a demo window open, you can set:

```powershell
$env:EMULATOR_UI_DEMO_AUTOCLOSE_MS = "1500"
swift run EmulatorHost ui-demo
```

For the automated block-2 validation path, run:

```powershell
$env:EMULATOR_UI_DEMO_VALIDATE = "1"
$env:EMULATOR_UI_DEMO_AUTOCLOSE_MS = "1500"
swift run EmulatorHost ui-demo
```

That mode scripts one native click against the live `Sessions` interaction region and prints `ui-demo validation: PASS` only if the window rendered, the scripted click was dispatched through the native hit-test path, and the scene advanced to the sessions screen.

## Generic App SDK

Third-party apps target the simplified environment by depending on `EmulatorAppSDK` from a local path package and adding an `EmulatorApp.json` file at the package root:

```json
{
  "product": "StarterTelemetryApp",
  "module": "StarterTelemetryApp",
  "registrationType": "StarterTelemetryRegistration"
}
```

The SDK provides:

- `EmulatorAppRegistration` with static `manifest` and `makeController()`
- `EmulatorServiceAwareAppRegistration` for apps that want typed host services during controller creation
- `EmulatorAppController` with `makeDocument()` and `handle(action:)`
- `EmulatorAppManifest` for app metadata and supported renderers
- `EmulatorCapability` and `requiredCapabilities` for app-declared host service needs
- `EmulatorHostServiceRegistry` and `EmulatorHostServices` for capability validation and typed service access
- `EmulatorBluetoothService` for generic GATT scan/connect/discover/read/write/subscribe flows
- `EmulatorLifecycleAwareAppController` for controllers that need startup and shutdown hooks
- `EmulatorRenderEnvironmentAwareAppController` for controllers that build documents from the resolved device and renderer environment
- `EmulatorInputAwareAppController` for controller-owned keyboard/back handling
- `EmulatorTextInputAwareAppController` for single-line editable text fields
- `EmulatorPointerAwareAppController` for pointer phase routing
- `EmulatorGestureAwareAppController` for synthetic drag/swipe/long-press/pinch/rotate events
- `EmulatorLifecycleEventAwareAppController` for foreground/background and device-environment changes
- `EmulatorUIInvalidationService` for background redraw requests
- `EmulatorDiagnosticsService` for app-defined trace markers and warning events
- `EmulatorAssetCatalog` for PNG images, named colors, and localized strings
- re-exported UI/rendering primitives from `RendererCore`

The external example package lives in [Examples/StarterTelemetryApp](Examples/StarterTelemetryApp) and demonstrates:

- resource-backed PNG rendering
- named colors from `Colors.json`
- localized strings from `Strings/en.json` and `Strings/fr.json`
- required capabilities for clock, logging, and storage
- persistent launch counting through the storage service
- structured logging through the host logger
- navigation, lists, gauges, and button-driven state updates

The Bluetooth example package lives in [Examples/BluetoothTelemetryApp](Examples/BluetoothTelemetryApp) and demonstrates:

- required capabilities for Bluetooth, logging, and clock access
- generic GATT scanning, connection, service discovery, characteristic discovery, reads, writes, and notifications
- deterministic mock Bluetooth runs in both text and Win32 renderers
- background packet updates flowing through the UI invalidation service into the native Win32 redraw path

The device environment example package lives in [Examples/DeviceShowcaseApp](Examples/DeviceShowcaseApp) and demonstrates:

- safe-area-aware root layout
- portrait vs landscape layout differences
- keyboard-focusable buttons and list rows
- controller-owned back handling through the input event surface
- visible foreground/background and orientation-change status updates

The advanced input example package lives in [Examples/InputPlaygroundApp](Examples/InputPlaygroundApp) and demonstrates:

- single-line text entry with a visible caret
- submit and backspace behavior routed through controller-owned text state
- pointer phase reporting
- drag and swipe state updates
- long-press counting
- synthetic pinch and rotate meters

## Bluetooth Backends

- `auto`: prefer the live WinRT backend on the Win32 renderer when it is usable, otherwise fall back to the deterministic mock backend
- `mock`: always use the deterministic UART-style sample peripheral and scripted packet stream
- `winrt`: require the live Windows Bluetooth adapter path and fail validation or run if it is unavailable

Today the automated acceptance flow uses the mock backend. The WinRT backend is implemented for native Windows hosts with a usable BLE adapter and compatible nearby devices, but it remains host-dependent and is validated manually rather than in the CI-style integration suite.

## Device Environment And Lifecycle

- `EmulatorDevicePreset` currently includes `phoneCompact`, `phoneTall`, and `tablet`
- `EmulatorDeviceOrientation` currently includes `portrait` and `landscape`
- `ScreenDocument` defaults to safe-area-constrained root layout; apps can opt into `fullBleed`
- text rendering stays one-shot, but it now honors the resolved device content frame
- Win32 rendering supports keyboard focus, visible focus rings, and redraw on lifecycle or orientation changes

The automated block-6 UI validation path still runs through `ui-demo`, but it now proves:

- a native window opened
- keyboard navigation moved focus
- a native activation changed visible state
- one background/resume cycle was delivered
- one orientation change caused a redraw and document rebuild
- single-line text entry and submit were delivered
- drag, long press, synthetic pinch, and synthetic rotate updated visible state

## Experimental Objective-C Runtime Track

The Objective-C layer is explicitly experimental and not Apple-compatible. It exists to validate bridge structure, lifetime management, selector registration, and a minimal message-send path.

- `RuntimeObjCExperiment` is the Swift wrapper used by the host and tests.
- `CObjCExperimentShim` is the stable C ABI boundary for the experiment.
- `.\scripts\bootstrap-libobjc2.ps1 -Architecture <x64|arm64>` prepares an external `gnustep/libobjc2` checkout and an architecture-specific build directory on Windows using CMake and Clang, isolated from the Swift package.
- When `vendor/libobjc2-build-<arch>/objc.dll` is present, `objc-check` and the Objective-C experiment can require that real runtime backend on Windows instead of the embedded fallback.

Today the experiment validates selector registration, sample class registration, instance allocation, retain/release, class lookup, `respondsToSelector`, class-name introspection, autorelease-pool scope, and a compatibility suite covering richer typed wrapper checks. It still does not claim UIKit, Apple framework overlays, or native iOS binary execution on Windows.

## Layout

- `RuntimeCore`: shared runtime protocols, configuration models, allocation/threading/library-loading abstractions
- `RuntimeWin32`: native Windows runtime implementation and host services
- `RuntimePOSIX`: legacy WSL/Linux runtime kept as a comparison path
- `RuntimeFFI`: Swift wrapper around the C bridge for callbacks, strings, and bytes
- `RuntimeObjCExperiment`: Swift wrapper around the experimental Objective-C bridge
- `CRuntimeShim`: plain C ABI surface for callbacks and round-trip validation
- `CObjCExperimentShim`: plain C ABI surface for the Objective-C experiment
- `RendererCore`: declarative DSL, retained render tree, layout tree, draw commands, and interaction routing
- `EmulatorAppSDK`: developer-facing compatibility SDK and resource catalog for external apps
- `CBluetoothWinRTShim`: native Bluetooth shim boundary for the experimental WinRT backend
- `EmulatorOnboarding`: config parsing and generated runner workspace support for external packages
- `RendererText`: terminal renderer used for smoke previews on top of the shared pipeline
- `RendererWin32`: Swift wrapper that bridges the shared pipeline into the native Windows window host
- `CRendererWin32Shim`: Direct2D + DirectWrite Win32 backend that owns the `HWND` and event loop
- `SmokeApp`: sample app module used to prove lifecycle sequencing
- `EmulatorHost`: CLI entrypoint for `doctor`, `ffi-check`, `objc-check`, `smoke`, `ui-demo`, and external `app` commands
