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

4. `DelayBuffer::read` dispatches through a member-function pointer on every read.

   The interpolator is chosen at construction but invoked indirectly per sample, so it cannot be inlined.

   Locations: `Sources/DSPHeaders/include/DSPHeaders/DelayBuffer.hpp:81`, `Sources/DSPHeaders/include/DSPHeaders/DelayBuffer.hpp:91`

   Recommendation: make the interpolator a template parameter or switch on a stored enum.

5. `PhaseShifter::process` recomputes values per sample that change only when coefficients are updated.

   The gamma products depend only on each filter's `a0`, which changes only in `updateCoefficients` (every 10 samples by default), yet they are recomputed every sample. The `1.0` literal in the output denominator also promotes that expression to `double`.

   Locations: `Sources/DSPHeaders/include/DSPHeaders/PhaseShifter.hpp:107`, `Sources/DSPHeaders/include/DSPHeaders/PhaseShifter.hpp:118`

   Recommendation: compute `gammas_` and the reciprocal of `1 + intensity_ * gammas_.back()` in `updateCoefficients`, and multiply by the cached reciprocal per sample.

### Low

6. Float code is silently promoted to `double`.

   `unipolarToBipolar`, `bipolarToUnipolar`, and `bipolarModulation` use double literals, so float inputs produce `double` results. `Interpolation::linear` and `cubic4thOrder` take `double` parameters, so `DelayBuffer<float>` converts on every read. The cubic weights table holds 32 KB of doubles.

   Location: `Sources/DSPHeaders/include/DSPHeaders/DSP.hpp:24`

   Recommendation: write literals as `ValueType{...}` so float code stays in float.

7. `Accelerated` stores its routines in writable static variables.

   Because the pointers are mutable globals, each call loads the pointer and calls indirectly.

   Location: `Sources/DSPHeaders/include/DSPHeaders/Accelerated.hpp:22`

   Recommendation: use `static constexpr` pointers or plain inline overloads so calls go directly to vDSP.

8. `forceMinToZero` makes four comparisons per sample per filter.

   `PhaseShifter` calls it six times per sample.

   Location: `Sources/DSPHeaders/include/DSPHeaders/Biquad.hpp:262`

   Recommendation: `std::abs(value) <= noiseFloor ? 0 : value` gives the same result with one compare.

9. The per-sample `BusBuffers` API blocks vectorization.

   `addMono`, `addStereo`, `addAll`, and `addAlternating` null-check on every call and reach the buffers through a reference to a vector. `addAlternating` also computes `index % 2` per channel per sample.

   Location: `Sources/DSPHeaders/include/DSPHeaders/BusBuffers.hpp:75`

   Recommendation: add accessors that return channel pointers or spans once per block so kernels can write tight loops.

10. `processAndRender` has small per-block overhead.

    The frame count is written to the buffers three times per block, and `checkForParameterValueChanges` walks an `unordered_map` every block.

    Locations: `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:184`, `Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp:267`

    Recommendation: set the frame count once, and iterate a `std::vector` of registered parameters while keeping the map for address lookups.

## Related Correctness Observations

These are not performance issues but were found during the review.

- Parameter ramps may advance once per render block rather than once per frame. `checkForValueChange` steps a ramp once and is called once per `processAndRender`, so a 16-frame ramp would take 16 render calls. (`EventProcessor.hpp:206`, `Parameters/Base.hpp:92`)
- Reading a Biquad filter's coefficients advances its ramp. `gainValue()` and `storageComponent()` are `const` but go through the `mutable` `ramper_`, whose `coefficients()` steps the ramp. `PhaseShifter` reads each filter three times per sample, so a ramp would run three times too fast. (`Biquad.hpp:470`, `Biquad.hpp:475`, `Biquad.hpp:546`)
- `std::forward(coefficients)` cannot compile because `std::forward` requires an explicit template argument; `std::move` is intended. It is unnoticed because the overload is never instantiated. (`Biquad.hpp:521`)
