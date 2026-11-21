# C++23 Code Review

Date: 2026-11-21

This review covers the C++ and Objective-C++ library sources, with emphasis on correctness, C++23 conformance, and idiomatic resource and concurrency management. No source changes were made as part of the review.

## Findings

### Critical

1. ~~Event rendering can overrun or underflow the remaining frame count.~~ **Fixed 2026-11-21.**

   `EventProcessor::render` calculates `framesBefore` from the next event time but does not cap it to `framesRemaining`. If an event is scheduled after the current render block, subtracting `framesBefore` from the unsigned remaining count underflows and subsequent processing uses an enormous frame count.

   Location: `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:335`

   Resolution: rendering is capped at `std::min(framesBefore, framesRemaining)`, leaving a future event unprocessed for the next render call. `testFutureEventDoesNotExceedRenderBlock` verifies the processor renders exactly the requested frame count without applying the future parameter event.

2. ~~Parameter updates contain a C++ data race.~~ **Fixed 2026-11-21.**

   `Parameters::Base::setPending`, documented for calls outside the render thread, writes `rampRemaining_`. The render thread reads and writes that same non-atomic variable. Concurrent access is undefined behavior under the C++ memory model.

   Location: `Sources/DSPHeaders/include/DSPHeaders/Parameters/Base.hpp:55`

   Resolution: `setPending` now modifies only the atomic pending value. The render thread detects when the pending value differs from its private ramp target and restarts the ramp itself. `testPendingValueReplacesActiveRamp` verifies the replacement behavior.

### High

3. ~~`PhaseIncrement` reads uninitialized values.~~ **Fixed 2026-11-21.**

   `cachedFrequency_` and `increment_` have no initializers. The first `value()` call compares the frequency against an indeterminate `cachedFrequency_`; that is undefined behavior. An accidental equality could then return an indeterminate increment.

   Location: `Sources/DSPHeaders/include/DSPHeaders/PhaseIncrement.hpp:59`

   Resolution: the cached frequency and increment now initialize to zero. `testInitialZeroFrequency` verifies the first read is well-defined when the initial frequency is zero.

4. ~~`LowPassFilter` leaks its Accelerate setup and has undefined ownership semantics.~~ **Fixed 2026-11-21.**

   A setup returned by `vDSP_biquadm_CreateSetup` is destroyed only when replacing it with another setup. There is no destructor for the final setup. Implicit copying also duplicates the raw handle, so merely adding a destructor would introduce double-destruction.

   Locations: `Sources/DSPHeaders/include/DSPHeaders/LowPassFilter.hpp:58`, `Sources/DSPHeaders/LowPassFilter.mm:50`

   Resolution: `LowPassFilter` now destroys its setup in a noexcept destructor and explicitly disallows copying and moving. `testExclusiveSetupOwnership` verifies the ownership constraints.

5. ~~`PhaseShifter` can retain a dangling frequency-band reference.~~ **Fixed 2026-11-21.**

   The constructor accepts `const FrequencyBands&` and the object stores that reference. Passing a temporary `FrequencyBands` leaves `bands_` dangling once construction finishes.

   Locations: `Sources/DSPHeaders/include/DSPHeaders/PhaseShifter.hpp:65`, `Sources/DSPHeaders/include/DSPHeaders/PhaseShifter.hpp:137`

   Resolution: `PhaseShifter` now stores its six-element `FrequencyBands` by value. `testConstructionFromTemporaryFrequencyBands` verifies construction from a temporary band collection.

6. ~~`LowPassFilter` does not update its Nyquist-period cache key.~~ **Fixed 2026-11-21.**

   `lastNyquistPeriod_` is checked by `calculateParams` but never assigned after recalculation. The early-return cache therefore cannot work for a nonzero Nyquist period.

   Locations: `Sources/DSPHeaders/LowPassFilter.mm:15`, `Sources/DSPHeaders/LowPassFilter.mm:53`

   Resolution: `calculateParams` now records `lastNyquistPeriod_` with the other cache fields. `testCalculateParams` exercises a repeated, identical configuration.

### Medium

7. LFO phase normalization is incomplete, and invalid waveforms are undefined in release builds.

   `setPhase` wraps only values greater than or equal to one; negative phases remain negative. `increment` subtracts one only once, so an increment greater than one also escapes the documented normalized range. `WaveformGenerator` reaches the end of a non-void function after `assert(false)`, which is undefined behavior when assertions are disabled.

   Locations: `Sources/DSPHeaders/include/DSPHeaders/LFO.hpp:86`, `Sources/DSPHeaders/include/DSPHeaders/LFO.hpp:119`

   Recommendation: use a robust normalization operation for all finite phase values, validate the allowed frequency range, and provide a defined fallback or termination path for invalid enum values.

8. `BusBufferFacet::assignBufferList` assumes every channel is valid when the first one is.

   The method checks only `mBuffers[0].mData`, then later accesses every channel's pointer. A partially populated buffer list can produce invalid pointers. When using `inPlaceSource`, it also indexes it without first verifying a matching number of buffers.

   Location: `Sources/DSPHeaders/include/DSPHeaders/BusBufferFacet.hpp:55`

   Recommendation: validate buffer counts and data pointers for every channel before installing the list.

9. The intrusive reference count is not safe for concurrent retain and release operations.

   The load/compare/decrement sequence is not one atomic ownership transition. Concurrent releases can leak an object or access it after another thread has deleted it.

   Location: `Sources/DSPHeaders/include/DSPHeaders/IntrusiveReferenceCounted.hpp:23`

   Recommendation: if cross-thread ownership is supported, implement release with an atomic `fetch_sub`-style transition and appropriate ordering. Otherwise, document the type as single-thread-only and avoid suggesting concurrent safety through `std::atomic`.

10. The public headers rely on non-standard C++ facilities.

   `#import` and `M_PI` are compiler or platform extensions, not C++23 facilities. They reduce portability of what is otherwise exposed as a C++ library.

   Locations: `Sources/DSPHeaders/include/DSPHeaders/Types.hpp:3`, `Sources/DSPHeaders/include/DSPHeaders/Biquad.hpp:102`

   Recommendation: use `#include` for C++ headers and `std::numbers::pi_v<T>` from `<numbers>`.

## Validation

The project was built for testing successfully after the item 1 fix. The remaining findings are behavioral and standards-conformance issues that do not currently cause a build failure.
