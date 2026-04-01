# Generic Emulator Platform Roadmap

## Purpose

This document replaces the remaining app-specific roadmap from the original research report with a platform roadmap for a **generic, simplified Swift app emulator on Windows**.

The project is no longer aiming to "run `lap_mobile` as-is" or to reproduce a full iOS runtime. The current product direction is:

- a native Windows host
- a repo-owned SwiftUI-inspired compatibility SDK
- a deterministic renderer with text and Win32 backends
- a controlled onboarding path for third-party local Swift packages
- a service/shim layer that can be extended over time

This document does three things:

1. records the scope change from the original report
2. defines the next block in detail
3. captures the remaining misses from the original block 1 so they are not lost

## Current Status

Completed:

- Block 1: native Windows Swift runtime foundation, FFI bridge, Objective-C experiment
- Block 2: retained UI engine, shared layout pipeline, terminal and Win32 rendering
- Block 3: generic app onboarding, `EmulatorAppSDK`, resource-backed example package

Current validated host commands:

- `doctor`
- `ffi-check`
- `objc-check`
- `smoke`
- `ui-demo`
- `app validate --package-path <path>`
- `app run --package-path <path> --renderer text|win32`

## Scope Shift From The Original Research Report

The original report assumed an app-specific emulator focused on `lap_mobile`, BLE, and possibly a deeper iOS runtime. That is no longer the primary product shape.

### What We Keep

- Windows-native Swift foundation
- custom UI/render pipeline
- Objective-C and C-ABI experimentation where useful
- future Bluetooth integration as an optional host service
- input/device simulation as a later capability

### What We Explicitly De-Scope

- running arbitrary iOS app binaries unchanged
- full UIKit or full SwiftUI compatibility
- full Apple framework coverage
- VM-based iOS execution as a product milestone
- making `lap_mobile` the central roadmap driver

### What Replaces The Old App-Specific Blocks

- old block 3 ("port `lap_mobile` views") becomes generic app onboarding and SDK work
- old blocks 4 and 5 (BLE-specific) become a broader host services and plugin architecture first, then concrete adapters like Bluetooth
- old block 6 (virtualization) becomes a research track, not a delivery block

## Remaining Misses From The Original Block 1

Block 1 is complete for the **new scoped project**, but not every promise from the original wording should be treated as finished.

### Done Relative To The New Scope

- native Swift runs on Windows `x64`
- a runtime skeleton exists for memory/thread/library-loading abstractions
- a Win32 host runtime exists
- a C ABI and Objective-C experiment exist

### Still Missing Relative To The Original Wording

1. True `arm64` runtime validation on real hardware
   The toolchain seam exists, but the project has not yet been validated on a real Windows `arm64` machine.

2. Stronger Objective-C environment coverage
   The current Objective-C layer is still experimental. It is sufficient for bridge validation, not for broad Cocoa-style compatibility.

3. "Launch iOS code" in the literal sense
   The project runs code that targets the emulator SDK, not unchanged iOS application code.

4. Formal runtime hardening
   Crash isolation, better diagnostics, ABI-versioning, and compatibility reporting are still future work.

These misses should not block the next platform block, but they should be preserved as a technical debt track.

## Updated Roadmap

| Block | Name | Goal |
| --- | --- | --- |
| 4 | Host Services SDK + Plugin Architecture | Define how apps ask for services and how the host provides them |
| 5 | Bluetooth Service Adapter | Add a first real host service with a RaceBox-oriented BLE implementation |
| 6 | Input, Device, And Lifecycle Simulation | Add touch/keyboard/device events, safe areas, viewport presets, app lifecycle |
| 7 | Storage, Network, And Devtools | Add persistence/network shims plus debugging and compatibility tooling |
| 8 | Compatibility Hardening | Stabilize APIs, publish support matrix, expand tests, package the platform |
| R1 | Optional Research Track | Real `arm64` validation, deeper Objective-C support, virtualization research |

## Next Block: Block 4

# Block 4 Plan: Host Services SDK + Plugin Architecture

## Summary

Block 4 turns the current renderer/runtime platform into a real application platform by adding a formal service boundary between the app SDK and the Windows host.

The key shift is:

- apps stop depending only on rendering primitives
- apps gain a controlled way to declare required capabilities
- the host gains a typed registry for built-in and future pluggable services

This is the prerequisite for Bluetooth, storage, networking, sensors, and later device simulation.

## Goals

- let app authors declare which host services they need
- let the host validate those requirements before run
- provide stable service access from app controllers
- keep the current onboarding model based on local Swift packages
- support built-in mock/default services first
- prepare the architecture for a later BLE adapter without baking BLE directly into the SDK core

## Non-Goals

- no real Bluetooth implementation yet
- no plugin marketplace
- no remote package loading
- no arbitrary dynamic code loading from untrusted sources
- no full permission UI or mobile settings system yet

## Public Interfaces To Add

### `EmulatorCapability`

Represents a declared app requirement. Initial cases:

- `bluetooth`
- `storage`
- `network`
- `clock`
- `logging`
- `clipboard`

### `EmulatorHostServices`

Typed container exposed to app controllers. It should provide accessors for built-in service protocols.

### `EmulatorHostServiceRegistry`

Host-side registry that resolves implementations for declared capabilities and validates missing requirements before app launch.

### `EmulatorAppManifest` Extensions

Extend the existing manifest with:

- `requiredCapabilities: Set<EmulatorCapability>`
- `preferredLocales: [String]`

### `EmulatorAppController` Update

Replace or extend controller construction so the app can receive services explicitly:

- `static makeController(services: EmulatorHostServices) -> any EmulatorAppController`

If source compatibility matters, keep the zero-argument constructor path as a defaulted overload during migration.

### Service Protocols

Add the first host-facing protocols to `EmulatorAppSDK`:

- `EmulatorClockService`
- `EmulatorStorageService`
- `EmulatorNetworkService`
- `EmulatorLoggingService`
- `EmulatorClipboardService`

The protocols should stay intentionally thin and synchronous/asynchronous only where necessary.

## Implementation Changes

### 1. SDK Service Layer

Add a new service namespace in `EmulatorAppSDK`:

- capability enums and manifest support
- host service protocols
- `EmulatorHostServices` facade
- convenience default implementations for tests and simple apps

This becomes the app-authoring seam for anything beyond UI state.

### 2. Host Validation And Launch Changes

Extend onboarding validation so `app validate` checks:

- declared capabilities are recognized
- the host can supply implementations for every required capability
- the generated runner uses the new registration/controller shape

Extend `app run` so service resolution happens before app boot and failures are surfaced as readable validation errors.

### 3. Runner Generation Changes

Update the generated runner workspace to:

- build an `EmulatorHostServiceRegistry`
- resolve `EmulatorHostServices`
- pass services into the app registration/controller entrypoint
- print a compact capability summary during validation

### 4. Built-In Host Services

Ship block 4 with host-provided implementations for:

- `clock`: monotonic clock and wall-clock access
- `storage`: package-scoped app data directory under `.emulator-cache/apps/<app-id>`
- `logging`: structured host logger forwarding to stdout and optional file log
- `network`: an initially narrow HTTP client abstraction
- `clipboard`: Windows clipboard on Win32, no-op or stub in text mode where needed

These services should work for both internal demos and external packages.

### 5. Mode-Aware Service Support

Some services may only be valid in some renderers or host modes. Add validation rules so the host can report:

- capability available
- capability degraded
- capability unavailable

For example, clipboard may be unavailable in text-mode test environments.

### 6. Example App Upgrade

Upgrade `Examples/StarterTelemetryApp` so it actually consumes at least:

- logging
- clock
- storage
- localized strings already present in block 3

This keeps block 4 grounded in a real external package, not only in host unit tests.

### 7. Documentation

Add a new developer-facing section to the docs covering:

- declaring capabilities in app code
- how validation fails when a service is missing
- which capabilities are currently built in
- how later blocks will add optional adapters like Bluetooth

## File-Level Changes Expected

Likely targets and files to touch:

- `Sources/EmulatorAppSDK/`
- `Sources/EmulatorOnboarding/`
- `Sources/EmulatorHost/`
- `Examples/StarterTelemetryApp/`
- `README.md`
- new tests under `Tests/EmulatorAppSDKTests/`, `Tests/EmulatorOnboardingTests/`, and host integration tests

## Test Plan

### Unit Tests

- capability parsing and manifest encoding/decoding
- service registry resolution
- missing capability errors
- mode-aware availability handling
- storage path scoping by app id
- clock and logging service behavior

### Integration Tests

- `swift run EmulatorHost app validate --package-path Examples/StarterTelemetryApp`
- `swift run EmulatorHost app run --package-path Examples/StarterTelemetryApp --renderer text`
- Windows-only:
  - `swift run EmulatorHost app run --package-path Examples/StarterTelemetryApp --renderer win32 --autoclose-ms 1500`

Additional assertions:

- validation output includes declared capabilities
- a missing required capability fails before launch
- the example app persists and reloads one small piece of state through the storage service

## Acceptance Criteria

Block 4 is complete when:

- external apps can declare required capabilities through the SDK
- the host validates capability availability before launch
- services are passed into app controllers through a typed API
- the example app uses at least two real host services
- `doctor`, `smoke`, `ui-demo`, and external app runs remain green
- no app needs to edit this repo's `Package.swift` to consume the platform

## Risks And Tradeoffs

### Too Many Services Too Early

If the SDK surface expands too fast, it will become hard to stabilize. Start with a thin service set and version it carefully.

### Overusing Dynamic Loading

The platform should keep compile-time validation where possible. Generated runners and typed entrypoints are preferable to runtime reflection.

### BLE Pressure Too Early

Bluetooth is important, but adding it before the generic service architecture would create another special case. Block 4 should keep BLE out of the core and prepare the seam first.

## Recommended Follow-Up Blocks

### Block 5: Bluetooth Service Adapter

Add:

- `EmulatorBluetoothService`
- Windows BLE implementation
- RaceBox-oriented integration example
- permission and availability reporting

This will absorb the spirit of the original blocks 4 and 5 without locking the platform to a single app.

### Block 6: Input, Device, And Lifecycle Simulation

Add:

- touch gestures
- keyboard-to-touch mapping
- viewport/device presets
- orientation changes
- safe areas
- foreground/background lifecycle events

### Block 7: Storage, Network, And Devtools Expansion

Expand:

- persistent state tools
- trace logs
- layout inspector
- action timeline
- compatibility warnings for unsupported APIs

### Block 8: Compatibility Hardening

Deliver:

- stable SDK versioning
- support matrix by feature
- packaging story
- broader end-to-end testing
- performance baselines

## Technical Debt Track From Original Block 1

These items should be carried alongside the roadmap, but not allowed to derail block 4:

1. Real Windows `arm64` validation
   Add CI or hardware validation for `arm64` once the host platform is stable enough.

2. Objective-C experiment hardening
   Improve diagnostics, loader behavior, and fallback clarity for the Objective-C bridge.

3. Runtime diagnostics
   Add better crash surfaces, command failure reporting, and ABI/version checks for generated runners.

4. Explicit compatibility statement
   Publish a short, stable statement that the platform runs apps targeting `EmulatorAppSDK`, not arbitrary iOS apps.

## Recommended Delivery Order

1. Service enums, manifest extensions, and SDK protocols
2. Host registry and validation errors
3. Generated runner updates
4. Built-in clock/logging/storage services
5. Example app migration
6. Integration tests and docs

## Definition Of Done For The New Scope

The project should be considered on-track after block 4 if:

- the platform can onboard third-party apps
- the platform can supply host services through stable SDK contracts
- later adapters like BLE can be built as services instead of special-case hacks
- the remaining misses from original block 1 are explicitly tracked rather than silently ignored

