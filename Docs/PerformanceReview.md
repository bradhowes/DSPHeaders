# C++ Performance Review

Date: 2026-11-21

This review covers the C++ and Objective-C++ library sources, with emphasis on code that runs on the audio render thread. Costs are estimated from reading the code; no benchmarks were run. No source changes were made as part of the review.

## Findings

### High

1. ~~`LFO::quadPhaseValue` and `negativeQuadPhaseValue` call `fmod` on most samples.~~ **Fixed 2026-11-21.**

   `wrappedModuloCounter` calls `std::fmod` whenever its input is outside `[0, 1)`. `phase_ + 0.25` is out of range for 25% of the cycle and `phase_ + 0.75` for 75% of it, so `negativeQuadPhaseValue` takes the slow library call on about three of every four samples. A single subtraction does the same job for these inputs.

   Locations: `Sources/DSPHeaders/include/DSPHeaders/LFO.hpp:101`, `Sources/DSPHeaders/include/DSPHeaders/LFO.hpp:104`, `Sources/DSPHeaders/include/DSPHeaders/LFO.hpp:130`

   Resolution: `wrappedModuloCounter` now returns values in `[0, 1)` unchanged, subtracts 1 for values in `[1, 2)`, and adds 1 for values in `(-1, 0)`. Only larger magnitudes and non-finite values reach the `fmod` path. The subtraction is exact for that range, so results are bit-identical to `fmod`, with one intentional exception: a tiny negative value plus 1 rounds to exactly 1, outside the normalized range, so it now wraps to 0. `testPhaseWrappingMatchesFmod` compares the results with an `fmod` reference across a sweep of values and at each range boundary, and `testTinyNegativePhaseWrapsToZero` covers the rounding case.

2. ~~The render thread logs.~~ **Fixed 2026-11-21.**

   `os_log_info` runs for each event-handling pass, each `processEventsUntil` call, each parameter or MIDI event, and each `setImmediateParameterValue` reached from a render event. It is cheap when info logging is disabled, but when logs are being streamed in Console or Instruments it formats and does IPC on the audio thread, which can cause dropouts and change timing while debugging.

   Locations: `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:226`, `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:293`, `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:330`, `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:384`

   Recommendation: remove logging from the render path, or put it behind a compile-time flag that defaults to off. Keep the rare error paths.

   Resolution: render-path logging in `render`, `processEventsUntil`, and `setImmediateParameterValue` is now guarded by `if constexpr (renderLoggingEnabled)`, which is set from the `DSPHEADERS_RENDER_LOGGING` compiler flag and defaults to off, so the calls are not compiled in normal builds. Because the header is part of a Clang module, the flag must be set build-wide (for example `-DDSPHEADERS_RENDER_LOGGING=1`). The two error logs in `processAndRender` remain. `setRendering` was listed in error: it runs only from `setRenderingFormat` and `deallocateRenderResources`, not on the render thread, so its log is unchanged. `testRenderLoggingDisabledByDefault` checks the default; building and running the event tests with the flag enabled exercises the logging branches.

### Medium

3. ~~The LFO calls its waveform through a function pointer, and its sine runs in double precision.~~ **Fixed 2026-11-21.**

   `valueGenerator_` makes every `value()` call indirect, which blocks inlining and vectorization of a kernel's per-sample loop. `sineValue` computes `std::sin` in `double` and converts the result to `ValueType`.

   Locations: `Sources/DSPHeaders/include/DSPHeaders/LFO.hpp:98`, `Sources/DSPHeaders/include/DSPHeaders/LFO.hpp:139`

   Recommendation: switch on `waveform_` inline. Computing the sine in `ValueType` would be faster still but slightly changes the LFO output.

   Resolution: the function pointer is gone; `generate` switches on `waveform_` inline, and an invalid waveform still produces a sinusoid after a debug assertion. `sineValue` now computes `std::sin(2π · phase)` in `ValueType`, which equals the previous `sin(π − 2π · phase)` mathematically, so float oscillators use single-precision sine. Float output now differs from the previous double-precision result by float rounding only. `testSinusoidMatchesDoublePrecision` checks that difference stays within 1e-6 across 4,096 phases, and `testSetWaveformChangesGenerator` checks that each waveform takes effect after `setWaveform`.

4. ~~`DelayBuffer::read` dispatches through a member-function pointer on every read.~~ **Fixed 2026-11-21.**

   The interpolator is chosen at construction but invoked indirectly per sample, so it cannot be inlined.

   Locations: `Sources/DSPHeaders/include/DSPHeaders/DelayBuffer.hpp:81`, `Sources/DSPHeaders/include/DSPHeaders/DelayBuffer.hpp:91`

   Recommendation: make the interpolator a template parameter or switch on a stored enum.

   Resolution: the interpolator is now a template parameter, `DelayBuffer<ValueType, DelayBufferInterpolator InterpolatorKind = linear>`, and `read` selects it with `if constexpr`, so the call is direct and inlinable. The enum moved to namespace scope as `DelayBufferInterpolator`; `DelayBuffer<T>::Interpolator` remains as an alias and `interpolator` exposes the chosen kind. This is a source-breaking change: the constructor no longer takes an interpolator, so code such as `DelayBuffer<float>(size, DelayBuffer<float>::Interpolator::cubic4thOrder)` must become `DelayBuffer<float, DelayBufferInterpolator::cubic4thOrder>(size)`, and old calls fail to compile rather than silently using linear. Interpolated values are unchanged; the existing interpolation tests pass with their original expected values, and `testInterpolatorSelection` checks the default, the exposed kind, and that each kind interpolates differently.

5. ~~`PhaseShifter::process` recomputes values per sample that change only when coefficients are updated.~~ **Fixed 2026-11-21.**

   The gamma products depend only on each filter's `a0`, which changes only in `updateCoefficients` (every 10 samples by default), yet they are recomputed every sample. The `1.0` literal in the output denominator also promotes that expression to `double`.

   Locations: `Sources/DSPHeaders/include/DSPHeaders/PhaseShifter.hpp:107`, `Sources/DSPHeaders/include/DSPHeaders/PhaseShifter.hpp:118`

   Recommendation: compute `gammas_` and the reciprocal of `1 + intensity_ * gammas_.back()` in `updateCoefficients`, and multiply by the cached reciprocal per sample.

   Resolution: `updateCoefficients` now computes `gammas_` and caches `outputScale_`, the reciprocal of `1 + intensity_ * gammas_.back()` computed in `ValueType`. `setIntensity` refreshes the cached scale. `process` keeps only the per-sample weighted sum and multiplies by the cached scale instead of dividing. Output changes only by rounding from the reciprocal and from dropping the `double` promotion; `testPhaseShifters` still matches Pirkle's implementation within 1e-5. `testSetIntensityUpdatesOutput` fails if `setIntensity` stops refreshing the cache (verified by temporarily removing the refresh), and `testResetMatchesNewInstance` checks that `reset` rebuilds the cached values.

### Low

6. ~~Float code is silently promoted to `double`.~~ **Fixed 2026-11-21.**

   `unipolarToBipolar`, `bipolarToUnipolar`, and `bipolarModulation` use double literals, so float inputs produce `double` results. `Interpolation::linear` and `cubic4thOrder` take `double` parameters, so `DelayBuffer<float>` converts on every read. The cubic weights table holds 32 KB of doubles.

   Location: `Sources/DSPHeaders/include/DSPHeaders/DSP.hpp:24`

   Recommendation: write literals as `ValueType{...}` so float code stays in float.

   Resolution: the `DSP.hpp` helpers are now constrained to `std::floating_point` and compute and return `ValueType`. `Interpolation::linear` and `cubic4thOrder` take their type from `partial` and convert the samples to it, so existing calls with integer sample values still work. `Cubic4thOrder` is now a class template on `ValueType` whose `constexpr` weights table is built at compile time in the header, so float interpolation reads a 16 KB float table instead of converting each double weight; the weights are computed in double and rounded, so the double table is unchanged. This removed the static tables in `DSPHeaders.mm`, which was deleted, and changes `Cubic4thOrder::` to `Cubic4thOrder<T>::` for anyone using it directly. `PhaseShifter` no longer stores the modulated frequency in a `double`, and the LFO's phase wrapping and square wave use `ValueType` literals. The LFO changes, `unipolarToBipolar`, and `bipolarToUnipolar` give bit-identical float results; `bipolarModulation`, `decibelToLinear`, and float interpolation differ by float rounding only. Double results are unchanged. `testFloatInputsStayFloat` checks the return types, `testFloatInterpolationMatchesDouble` checks float interpolation against the double path within 1e-6, and `testCubicWeightTables` checks that each float weight is the rounded double weight.

7. ~~`Accelerated` stores its routines in writable static variables.~~ **Fixed 2026-11-21.**

   Because the pointers are mutable globals, each call loads the pointer and calls indirectly.

   Location: `Sources/DSPHeaders/include/DSPHeaders/Accelerated.hpp:22`

   Recommendation: use `static constexpr` pointers or plain inline overloads so calls go directly to vDSP.

   Resolution: the four routine pointers are now `static constexpr`, so the compiler knows each target and emits direct calls. Callers are unchanged. `static_assert`s in `TypesTests.mm` check at compile time that each pointer is a constant naming the expected float or double vDSP routine.

8. ~~`forceMinToZero` makes four comparisons per sample per filter.~~ **Fixed 2026-11-21.**

   `PhaseShifter` calls it six times per sample.

   Location: `Sources/DSPHeaders/include/DSPHeaders/Biquad.hpp:262`

   Recommendation: `std::abs(value) <= noiseFloor ? 0 : value` gives the same result with one compare.

   Resolution: `forceMinToZero` now uses `std::abs(value) <= noiseFloor`. Results are identical except that `-0.0` now returns `+0.0`, which compares equal and is inaudible. NaN still passes through unchanged. `testForceMinToZero` compares the new code with the previous implementation at zero, values just inside and outside the noise floor, the smallest denormal, normal samples, infinity, and NaN.

9. ~~The per-sample `BusBuffers` API blocks vectorization.~~ **Fixed 2026-11-21.**

   `addMono`, `addStereo`, `addAll`, and `addAlternating` null-check on every call and reach the buffers through a reference to a vector. `addAlternating` also computes `index % 2` per channel per sample.

   Location: `Sources/DSPHeaders/include/DSPHeaders/BusBuffers.hpp:75`

   Recommendation: add accessors that return channel pointers or spans once per block so kernels can write tight loops.

   Resolution: `BusBuffers` gains `channel(index, frameCount)`, which returns a `std::span<AUValue>` over one channel's samples (empty if the channel has no buffer), and `channels()`, which returns the channel pointers as a span. Kernels call these once per render block and loop over plain spans, with no per-sample indirection or null checks; the class comment shows the pattern. `addAlternating` now walks channels in even/odd pairs instead of computing `index % 2` per channel. The existing per-sample methods are otherwise unchanged, so current kernels keep working, and the speedup applies as kernels adopt the span accessors. `testChannelSpans` covers the accessors, including a channel without a buffer, and `testAddAlternatingChannelCounts` covers one to five channels with a missing buffer.

10. ~~`processAndRender` has small per-block overhead.~~ **Fixed 2026-11-21.**

    The frame count is written to the buffers three times per block, and `checkForParameterValueChanges` walks an `unordered_map` every block.

    Locations: `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:184`, `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:267`

    Recommendation: set the frame count once, and iterate a `std::vector` of registered parameters while keeping the map for address lookups.

    Resolution: the `inputFacet_.setFrameCount` call is removed. Both facets refer to the same `output` buffer list, and `pullInput` sets the frame count before pulling, so the frame count is now written once per block without upstream input and twice with it. The write on the output facet stays because `pullInput` checks the buffer size before writing it, and removing it would change that check. `EventProcessor` now also keeps `parameterList_`, a vector of the registered parameters filled in `registerParameter`, and `checkForParameterValueChanges` and `renderingStateChanged` iterate it instead of the hash map; the map remains for lookups by address. The existing pull-input and in-place rendering tests cover the frame-count change, and `testAllRegisteredParametersAreChecked` checks that pending changes and ramp cancellation reach every registered parameter.

## Related Correctness Observations

These are not performance issues but were found during the review.

- ~~Parameter ramps may advance once per render block rather than once per frame.~~ **Resolved 2026-11-21.** Advancing once per render call is intentional (commit `6ab8580`), replacing per-frame rendering during ramps. The real defect was that host ramps from `AURenderEventParameterRamp` passed `rampDurationSampleFrames`, which Apple defines in sample frames, as a count of render calls, so a 512-frame ramp in 512-frame blocks lasted 512 calls (about 6 s at 44.1 kHz) instead of one. `processEventsUntil` now converts it with `rampFramesToRenderCalls`, rounding up. A zero-length ramp also underflowed `duration - 1` and left `rampRemaining_` near 4 billion; it is now an immediate change. Comments that called these durations "frames" now say "render calls". `testHostRampDurationIsInFrames` and `testZeroLengthHostRampIsImmediate` cover both. (`EventProcessor.hpp`, `Parameters/Base.hpp`)
- ~~Reading a Biquad filter's coefficients advances its ramp.~~ **Fixed 2026-11-21.** `Ramper` now has a `const` `coefficients()` that only reads and an `advance()` that `transform` calls once per sample, so `gainValue()` and `storageComponent()` no longer step the ramp and `ramper_` is no longer `mutable`. An immediate `setCoefficients` now also cancels an active ramp; before, the stale ramp kept running and ended at its old goal. `testReadingCoefficientsDoesNotAdvanceRamp` and `testImmediateCoefficientsCancelRamp` cover both. `gainValue()` and `storageComponent()` are `const` but go through the `mutable` `ramper_`, whose `coefficients()` steps the ramp. `PhaseShifter` reads each filter three times per sample, so a ramp would run three times too fast. (`Biquad.hpp:470`, `Biquad.hpp:475`, `Biquad.hpp:546`)
- ~~`std::forward(coefficients)` cannot compile~~ **Fixed 2026-11-21** by removing the rvalue `setCoefficients`, `start`, and `setupRamp` overloads, which duplicated the `const&` versions for a five-value type. `Filter`'s own rvalue overload forwarded a named lvalue, so the broken one was never reached. The unused, uncompilable private `coefficients()` "only used by RampingAdapter" was also removed. Original note: because `std::forward` requires an explicit template argument; `std::move` is intended. It is unnoticed because the overload is never instantiated. (`Biquad.hpp:521`)
- **Fixed 2026-11-21.** `DelayBuffer`'s cubic interpolation read one sample too far back. The `Cubic4thOrder` weights are Catmull-Rom weights that interpolate between the second and third of four samples, but `cubic4thOrderInterpolate` passed offsets `whole` through `whole + 3`, so fractional delays returned the value one sample older than requested while whole-number delays returned the right sample, giving jumps of up to 0.17 on a slow sine whenever a swept delay crossed a whole number. It now passes `whole - 1` through `whole + 2`, repeating the newest sample when the delay is under one sample. Compared against an independent Catmull-Rom formula and Pirkle's 4-point Lagrange interpolator on a known sine, the maximum error went from 0.17 to 0.00026 (linear: 0.0048), and the jumps are gone. `testCubicMatchesSignalAndIsContinuous` checks accuracy against the signal and continuity at whole-number delays, and the expected values in `testReadCubic4thOrderInterpolated`, which encoded the old offset, were recomputed. (`DelayBuffer.hpp`)
