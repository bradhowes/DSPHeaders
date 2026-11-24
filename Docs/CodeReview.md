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

7. ~~LFO phase normalization is incomplete, and invalid waveforms are undefined in release builds.~~ **Fixed 2026-11-21.**

   `setPhase` wraps only values greater than or equal to one; negative phases remain negative. `increment` subtracts one only once, so an increment greater than one also escapes the documented normalized range. `WaveformGenerator` reaches the end of a non-void function after `assert(false)`, which is undefined behavior when assertions are disabled.

   Locations: `Sources/DSPHeaders/include/DSPHeaders/LFO.hpp:86`, `Sources/DSPHeaders/include/DSPHeaders/LFO.hpp:119`

   Resolution: phase normalization now handles negative, multi-cycle, and non-finite inputs; normal single-cycle increments retain a fast path. Invalid waveform values now return a sinusoid generator after the debug assertion. `testPhaseNormalization` covers negative, multi-cycle, non-finite, and high-frequency phase updates.

8. ~~`BusBufferFacet::assignBufferList` assumes every channel is valid when the first one is.~~ **Fixed 2026-11-21.**

   The method checks only `mBuffers[0].mData`, then later accesses every channel's pointer. A partially populated buffer list can produce invalid pointers. When using `inPlaceSource`, it also indexes it without first verifying a matching number of buffers.

   Location: `Sources/DSPHeaders/include/DSPHeaders/BusBufferFacet.hpp:55`

   Resolution: `assignBufferList` now validates everything before changing any state. The buffer list must match the expected channel count, and its data pointers must be either all non-null or all null. For in-place rendering, the source must have a matching buffer count and non-null data for every channel. `testInPlaceRendering`, `testPartiallyPopulatedBufferList`, and `testInvalidInPlaceSource` cover these cases.

9. ~~The intrusive reference count is not safe for concurrent retain and release operations.~~ **Fixed 2026-11-21.**

   The load/compare/decrement sequence is not one atomic ownership transition. Concurrent releases can leak an object or access it after another thread has deleted it.

   Location: `Sources/DSPHeaders/include/DSPHeaders/IntrusiveReferenceCounted.hpp:23`

   Resolution: retain is now a relaxed `fetch_add`, and release is a single acquire-release `fetch_sub` that deletes only when it drops the last reference. Release also now deletes through `T*` rather than the base pointer, since the base class has no virtual destructor. `testRetainRelease` and `testConcurrentRetainRelease` verify that an instance is deleted exactly once, including under concurrent retain and release from multiple threads.

10. ~~The public headers rely on non-standard C++ facilities.~~ **Fixed 2026-11-21.**

   `#import` and `M_PI` are compiler or platform extensions, not C++23 facilities. They reduce portability of what is otherwise exposed as a C++ library.

   Locations: `Sources/DSPHeaders/include/DSPHeaders/Types.hpp:3`, `Sources/DSPHeaders/include/DSPHeaders/Biquad.hpp:102`

   Resolution: every public header now uses `#include`, and `Types.hpp` gained the `#pragma once` it had been relying on `#import` to supply. `Biquad.hpp` uses `std::numbers::pi_v<ValueType>`, and `LFO.hpp` uses `std::numbers::pi`, keeping its existing double-precision sine argument. The existing Biquad and LFO tests verify the numeric results are unchanged.

## Validation

All findings have been resolved. After the final fix (item 10), the full `DSPHeaders` test plan ran with all 107 tests passing.

# Second Review

Date: 2026-11-24

This pass revisits every library source after the fixes above and those in `PerformanceReview.md`. It covers correctness, C++23 style, and any performance left on the table. No source changes were made as part of the review. Items 11 and 19 were confirmed by running a small program against the headers; the rest come from reading the code.

## Findings

### Critical

11. ~~Kernels read the wrong input samples after a mid-block event.~~ **Fixed 2026-11-24.**

    When an event splits a render block, `makeFrames` moves the output facet to the current position with `outputFacet.setOffset(processed)` but never moves `inputFacet_`. Every segment after the first therefore gets input pointers that still point at frame 0. With in-place rendering, the input and output share storage, so the kernel re-processes samples it has already written. A kernel that writes `out[f] = in[f] + 1000` and gets a parameter event at frame 100 produces `out[100] == 2000` instead of 1100. Any host automation or MIDI event within a block corrupts the audio of an effect from that frame onward.

    Location: `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:392`

    Recommendation: when `inputFacet_.isLinked()`, call `inputFacet_.setOffset(processed)` alongside the output facet. The existing tests miss this because every mock kernel ignores its input buffers.

    Resolution: `makeFrames` now offsets `inputFacet_` along with the output facet whenever it is linked. Bypass is unaffected because `copyInto` computes its own offsets from the buffer list. Kernels now receive input for the frames they are rendering. That changes the output of any effect that reads its input and receives events within a render block, from wrong samples to the correct ones. `testInputAlignedWithOutputAfterMidBlockEvent` and `testInPlaceInputAlignedWithOutputAfterMidBlockEvent` use a kernel that derives each output from its input. With a parameter event at frame 100, they check the samples on both sides of the split, with both a host-supplied output buffer and in-place rendering. Both tests fail without the fix (8 failed assertions). The full test plan passes with 129 tests.

### High

12. ~~Errors on the render path call `std::terminate` instead of returning a status.~~ **Fixed 2026-11-24.**

    `processAndRender`, `render`, and `makeFrames` are `noexcept`, but they call `BusBufferFacet::assignBufferList`, `setOffset`, and `setFrameCount`, which throw `std::runtime_error` for a null list, a channel-count mismatch, or a partly populated buffer list. An exception leaving a `noexcept` function terminates the process, so a malformed buffer list from the host, or an interleaved format whose `mNumberBuffers` differs from `channelCount`, crashes the host app instead of failing the render. `deallocateRenderResources` is also `noexcept` and calls `BusSampleBuffer::release`, which throws if the buffer was already released, so calling it twice terminates.

    Locations: `Sources/DSPHeaders/include/DSPHeaders/BusBufferFacet.hpp:57`, `Sources/DSPHeaders/include/DSPHeaders/BusSampleBuffer.hpp:39`, `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:139`, `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:196`

    Recommendation: have `assignBufferList` return a status (or `std::expected<void, OSStatus>`) and have `processAndRender` return `kAudioUnitErr_FormatNotSupported` or `kAudioUnitErr_InvalidParameter`. Make `release` a no-op when nothing is allocated. Keep `assert` for the internal invariants. Exceptions do not belong on the render thread in any case, since throwing allocates.

    Resolution: nothing in the library throws any more. `BusBufferFacet::assignBufferList` is now `[[nodiscard]] noexcept` and returns an `AUAudioUnitStatus`: `noErr`; `kAudioUnitErr_FormatNotSupported` when the channel count of the list or in-place source does not match; or `kAudio_ParamError` for a null list, a partly populated list, or missing in-place storage. As before, it changes no state on failure. `processAndRender` checks the status for the output and input facets, logs it with `os_log_error`, and returns it to the host without rendering. On an unlinked facet, `setOffset`, `setFrameCount`, `copyInto`, `clear`, and `unlink` are now `noexcept` no-ops, and `pullInput` returns `kAudioUnitErr_Uninitialized`. `BusSampleBuffer::release` is `noexcept` and safe to call when nothing is allocated, so `deallocateRenderResources` can run twice. This is source-breaking for code that calls `assignBufferList` directly: it no longer throws, and ignoring its result now produces a warning. `BusBufferFacetTests` now checks the specific status codes in place of `XCTAssertThrows`. New tests cover the rest: `testNullBufferList` and `testUnlinkedFacetIsSafe` for the facet, `testReleaseWithoutAllocationIsSafe` for the sample buffer, and, for `EventProcessor`, `testInvalidBufferListReturnsStatus` (a mono list for a stereo effect, and a partly populated list) and `testDeallocateTwiceIsSafe`. The full test plan passes with 134 tests.

13. A default-constructed `Biquad::Filter` filters from indeterminate state.

    `Filter() = default` combined with `StateType state_;`, which has no initializer, means that a filter declared as a kernel member (`Biquad::Direct<> filter_;`) and not named in the constructor's initializer list is default-initialized. Its `x_z1`…`y_z2` are then indeterminate, and the first `transform` reads them. That is undefined behavior and in practice a burst of noise or NaN. `Coefficients` has the same problem, since its members have no initializers. `PhaseShifter` avoids it only because it writes `filters_{}`.

    Location: `Sources/DSPHeaders/include/DSPHeaders/Biquad.hpp:222`, `Sources/DSPHeaders/include/DSPHeaders/Biquad.hpp:234`, `Sources/DSPHeaders/include/DSPHeaders/Biquad.hpp:538`

    Recommendation: give `State` and `Coefficients` members default member initializers (`ValueType x_z1{};` and so on), and write `StateType state_{};`.

### Medium

14. Bypass without upstream input leaves the output buffer unwritten.

    In `makeFrames`, bypass with no linked input facet does nothing. The comment says "we have already zero'd out the output buffer", but nothing clears it, so an instrument in bypass emits whatever was in the host's buffer or in the internal `BusSampleBuffer` from earlier renders.

    Location: `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:393`

    Recommendation: call `outputFacet.busBuffers().clear(frameCount)` in that branch (the pointers are already offset), and fix the comment.

15. `inputFacet_` stays linked to buffers it no longer owns.

    `inputFacet_` is linked on the first render that has a `pullInputBlock` and is never unlinked: not by `deallocateRenderResources` (which unlinks only the output facets and then frees the buffers), and not when a later render has no `pullInputBlock`. After that, `doRendering` receives input pointers into freed or stale memory, and bypass (`inputFacet_.isLinked()` is still true) copies from them.

    Locations: `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:141`, `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:199`

    Recommendation: unlink `inputFacet_` in `deallocateRenderResources`, and at the start of `processAndRender` when `pullInputBlock` is null.

16. Host `AURenderEventParameter` events are ramped, not applied immediately.

    `processEventsUntil` passes `treeBasedRampDuration_` (16 render calls by default) for plain parameter events, so sample-accurate host automation lands about 16 blocks late. Apple defines `AURenderEventParameter` as an immediate change at `eventSampleTime`; ramps arrive as `AURenderEventParameterRamp`. This may be an intentional smoothing choice, but it is undocumented and differs from what hosts expect.

    Location: `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:431`

    Recommendation: pass 0 for `AURenderEventParameter`, or make the duration a documented setting. This changes behavior for the AUv3 effects that use the library.

17. The `Coefficients` builder methods are easy to misuse.

    `A0(…)` through `B2(…)` return a modified copy but are non-`const` and not `[[nodiscard]]`, so `coefficients.A0(1.0);` reads like a setter and silently does nothing.

    Location: `Sources/DSPHeaders/include/DSPHeaders/Biquad.hpp:65`

    Recommendation: mark them `[[nodiscard]] constexpr … const noexcept`. Do the same for `rampFactor`, and make `operator+=` return `Coefficients&`.

18. `module.modulemap` omits public headers.

    `Accelerated.hpp`, `BusBuffers.hpp`, `LowPassFilter.hpp`, and `Parameters/Bool.hpp` are not listed. `Parameters::Bool` is therefore not visible to Swift through the module, and the others are pulled into the module only as non-modular includes, which `-Wnon-modular-include-in-framework-module` reports.

    Location: `Sources/DSPHeaders/include/module.modulemap`

    Recommendation: list every header under `include/DSPHeaders`, or switch to `umbrella "DSPHeaders"`.

### Low

19. `ConstMath::log10` is wrong for integer arguments.

    It divides by `Constants<ValueType>::ln10`, which for `int` is `2`, so `ConstMath::log10(100)` returns 2.30 instead of 2. `log` correctly promotes integers to `double`, but `log10` does not use the promoted type for the divisor.

    Location: `Sources/DSPHeaders/include/DSPHeaders/ConstMath.hpp:343`

    Recommendation: use `Constants<IntegralAsDouble<ValueType>>::ln10`.

20. `DelayBuffer::read` has no defined behavior outside `[0, size() - 3]`.

    A negative delay makes `partial` negative, and in the cubic path `size_t(partial * TableSize)` converts a negative float to an unsigned type, which is undefined behavior. In release builds it reads outside the weights table. A delay at or beyond `size()` silently wraps to recent samples.

    Location: `Sources/DSPHeaders/include/DSPHeaders/DelayBuffer.hpp:85`

    Recommendation: document the precondition and `assert` it, or clamp the delay.

21. `LowPassFilter` can be used before it is configured.

    `magnitudes` indexes `F_[0..4]` and `apply` passes `setup_` to vDSP without checking that `calculateParams` has run. Both are out-of-bounds or null dereferences on a fresh instance. `LowPassFilter.mm` also includes `vForce.h` through a fragile `Accelerate/../Frameworks/...` path, uses no vForce routine, and has a detached doc comment for `filterBadValues`.

    Locations: `Sources/DSPHeaders/LowPassFilter.mm:3`, `Sources/DSPHeaders/LowPassFilter.mm:72`, `Sources/DSPHeaders/include/DSPHeaders/LowPassFilter.hpp:56`

22. `BusBufferFacet::pullInput`'s size check can never fail.

    `processAndRender` sets the output list's `mDataByteSize` to `frameCount * sizeof(AUValue)` just before `pullInput` compares against it, so the check is always true. It is harmless, since the capacity was already checked against `outputBus.capacity()`, but it suggests a protection that does not exist.

    Location: `Sources/DSPHeaders/include/DSPHeaders/BusBufferFacet.hpp:155`

23. `checkedVectorIndexing` is `noexcept` but may call `at()`.

    With `CHECKED_VECTOR_INDEXING=1`, an out-of-range index throws `std::out_of_range` out of a `noexcept` function and terminates, which defeats the purpose of the checked mode.

    Location: `Sources/DSPHeaders/include/DSPHeaders/Types.hpp:28`

    Recommendation: drop `noexcept` under the checked configuration, or use `assert` plus `operator[]`. The `size_t` overloads also duplicate the `SizableType` ones and can be removed.

24. Documentation and diagnostics are inaccurate.

    - `Transformer::boolIn` says "0.0 means false and anything else 1.0", but its threshold is 0.5.
    - The `LFO` class comment omits the square waveform. Its `sampleRate_` member is never read, and `setSampleRate` does not update it.
    - `Base` comments still say `rampDelta_` and `rampRemaining_` are per frame; they are per render call.
    - `os_log_error(…"%d > %d"…)` formats `UInt32` values. Use `%u`.
    - The pull-input failure in `processAndRender` is logged with `os_log_info` rather than `os_log_error`.

    Locations: `Parameters/Transformer.hpp:42`, `LFO.hpp:17`, `Parameters/Base.hpp:163`, `EventProcessor.hpp:191`, `EventProcessor.hpp:213`

## C++23 Style and Code Quality

These changes do not alter behavior unless noted.

- **Missing includes.** `BusBufferFacet.hpp` and `BusSampleBuffer.hpp` use `std::runtime_error` without `<stdexcept>`. `Types.hpp` derives from `std::array` without `<array>`. `ConstMath.hpp` uses `std::numeric_limits` without `<limits>`. All of them compile today only through transitive includes.
- **`std::to_underlying`.** `valueOf` duplicates C++23's `std::to_underlying`, and it has a stray `;` after its body.
- **`std::bit_ceil`.** `DelayBuffer::smallestPowerOf2For` computes `pow(2, ceil(log2(x)))` in floating point. `std::bit_ceil(size_t(std::ceil(x)))` from `<bit>` is exact and simpler.
- **Mutable static tables.** `PhaseShifter::ideal` and `nationalSemiconductor` are `inline static` non-`const` globals that any caller can overwrite. Make them `static constexpr FrequencyBands`. `setIntensity` takes a `double` while the member is `ValueType`.
- **Explicit conversions.** `Parameters::Bool::operator bool` is implicit, so a `Bool` silently converts to `int` in arithmetic; make it `explicit` (source-breaking only for such misuse). Mark the single-argument `DelayBuffer(double)`, `TypeErasedKernel(ProcessAndRender)`, and `RenderBlockShim(TypeErasedKernel)` constructors `explicit`.
- **Unnecessary copies.** `TypeErasedKernel` and `RenderBlockShim` take their argument by value and then copy it into the member; use `std::move`. `TypeErasedKernel::processAndRender_` re-spells the `ProcessAndRender` alias, and the captured `proc` does not need `__block`. The fallback render block returns `-1`; `kAudioUnitErr_Uninitialized` says what went wrong.
- **Rule of zero.** `Coefficients` declares the default copy and move members explicitly, and `Filter(CoefficientsType&&)` copies its "rvalue" anyway. Both can be deleted. `BusBufferFacet::setChannelCount` calls `reserve` immediately before `resize`, which does the same allocation.
- **Concept-constrained helpers.** `fromBool` and `toBool` are templates whose only use of `T` is a `static_assert` that pins it to one type. Plain functions taking `bool` and `AUValue` are clearer. `Accelerated<long double>` fails with an obscure lambda-return error; constrain it with `requires std::same_as<T, float> || std::same_as<T, double>`.
- **Sign-mixed loops.** `PhaseShifter` loops with `auto index = 0` against `size()` and `BandCount`, and `BusBuffers::clear` uses `UInt32` against `size()`. Use `size_t` or a range `for`, which also removes `-Wsign-compare` noise under the package's opt-in warnings.
- **Float promotion in Biquad.** `LPF1` and `HPF1` use `1.0` (a `double` literal), so float coefficients are computed partly in double, unlike the rest of the header after performance item 6. Use `ValueType{1}`.
- **Namespace hygiene.** `LFOWaveform` is declared in the global namespace. `LFO.hpp`, `PhaseIncrement.hpp`, and `PhaseShifter.hpp` include siblings as `"DSP.hpp"` instead of `"DSPHeaders/DSP.hpp"`. `Integral.hpp` pulls in all of `AVFoundation` and `Transformer.hpp` includes `<atomic>`, though neither uses them. `Concepts.hpp` (included by every parameter header) pulls in `BusBufferFacet.hpp` and AudioToolbox just to name `BusBuffers` in two concepts.
- **Pointless cast.** `processEventsUntil` uses `const_cast<AURenderEvent*>(event->head.next)`, but `next` is already a non-`const` pointer and is assigned to a pointer-to-`const`.
- **Precise `const`.** `getParameterValue` can be `const`. `LowPassFilter::apply` can take `const BusBuffers&` for its input.

## Performance

The render-thread hot spots were addressed in `PerformanceReview.md`, and no new significant costs were found. Remaining opportunities are small:

- `PhaseShifter::updateCoefficients` calls `std::tan` six times per update (every 10 samples by default) through `APF1`. A small `tan` approximation or table over the bands' fixed frequency ranges would remove most of the remaining per-sample cost of the shifter.
- `BusBufferFacet::setOffset` re-validates the buffer list and rewrites every channel pointer on each render segment. This is negligible per block, but fixing item 11 doubles it. A single `setOffset` that updates both facets keeps the cost flat.
- `LowPassFilter::calculateParams` may allocate on its first call or when the channel count grows (`F_.reserve`, `vDSP_biquadm_CreateSetup`). Call it once from `setRenderingFormat`-time code so the render thread only takes the `SetTargetsDouble` path.
