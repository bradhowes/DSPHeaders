// Copyright © 2021-2026 Brad Howes. All rights reserved.

#pragma once

#include <cassert>
#include <cmath>
#include <numbers>

#include "DSPHeaders/DSP.hpp"
#include "DSPHeaders/Parameters/Float.hpp"
#include "DSPHeaders/PhaseIncrement.hpp"

namespace DSPHeaders {

enum class LFOWaveform { sinusoid, triangle, sawtooth, square};

/**
 Implementation of a low-frequency oscillator. Can generate:

 - sinusoid
 - triangle
 - sawtooth
 - square

 The output is bipolar ([-1.0, 1.0]). Use DSP::bipolarToUnipolar to generate values in [0.0, 1.0].

 Loosely based on code found in "Designing Audio Effect Plugins in C++" by Will C. Pirkle (2019).

 The LFO operates at a frequency which is controlled by an AU parameter setting that can be adjusted in
 real-time. The LFO provides a facade for controlling this value, but internally, the value that is
 being managed is the phase increment that governs how the signal changes at each sample.
 */
template <typename ValueType = AUValue>
class LFO {
public:

  /**
   Create a new instance.

   @param frequency the frequency of the oscillator
   @param sampleRate number of samples per second
   @param waveform the waveform to emit
   */
  LFO(Parameters::Float& frequency, ValueType sampleRate, LFOWaveform waveform) noexcept
  : waveform_{waveform}, phaseIncrement_ {frequency, sampleRate} {
    assert(isValidWaveform(waveform));
    reset();
  }

  /**
   Create a new instance.

   @param frequency the frequency of the oscillator
   @param sampleRate number of samples per second
   */
  LFO(Parameters::Float& frequency, ValueType sampleRate) noexcept
  : LFO(frequency, sampleRate, LFOWaveform::sinusoid) {}

  /** Create a new instance.

   @param frequency the frequency of the oscillator
   */
  LFO(Parameters::Float& frequency) noexcept : LFO(frequency, 44100.0, LFOWaveform::sinusoid) {}

  /**
   Set the sample rate to use.

   @param sampleRate number of samples per second
   */
  void setSampleRate(ValueType sampleRate) noexcept {
    phaseIncrement_.setSampleRate(sampleRate);
  }

  /**
   Set the waveform to use

   @param waveform the waveform to emit
   */
  void setWaveform(LFOWaveform waveform) noexcept {
    assert(isValidWaveform(waveform));
    waveform_ = waveform;
  }

  /**
   Set the phase of the oscillator. By default, the oscillator will start at 0.0.

   @param phase the normalized phase to start at (0-1.0)
   */
  void setPhase(ValueType phase) noexcept {
    phase_ = wrappedModuloCounter(phase);
  }

  /// @returns current internal normalized phase value
  ValueType phase() const noexcept { return phase_; }

  /// Restart from a known zero state.
  void reset() noexcept { phase_ = 0.0; }

  /// @returns current value of the oscillator
  ValueType value() const noexcept { return generate(phase_); }

  /// @returns current value of the oscillator that is 90° ahead of what `value()` returns
  ValueType quadPhaseValue() const noexcept { return generate(wrappedModuloCounter(phase_ + ValueType{0.25})); }

  /// @returns current value of the oscillator that is 90° behind what `value()` returns
  ValueType negativeQuadPhaseValue() const noexcept {
    return generate(wrappedModuloCounter(phase_ + ValueType{0.75}));
  }

  /**
   Increment the oscillator to the next value.
   */
  void increment() noexcept {
    phase_ = wrappedModuloCounter(phase_ + phaseIncrement_.value());
  }

  /// @returns the current waveform in effect for the LFO
  LFOWaveform waveform() const noexcept { return waveform_; }

private:
  static bool isValidWaveform(LFOWaveform waveform) noexcept {
    switch (waveform) {
      case LFOWaveform::sinusoid:
      case LFOWaveform::sawtooth:
      case LFOWaveform::triangle:
      case LFOWaveform::square: return true;
    }
    return false;
  }

  /**
   Generate the waveform value for a phase. This switches on the waveform rather than calling through a function
   pointer so that the compiler can inline it into a kernel's per-sample loop. An invalid waveform produces a sinusoid.

   @param counter the normalized phase in [0, 1)
   @returns the waveform value in [-1, 1]
   */
  ValueType generate(ValueType counter) const noexcept {
    switch (waveform_) {
      case LFOWaveform::sawtooth: return sawtoothValue(counter);
      case LFOWaveform::triangle: return triangleValue(counter);
      case LFOWaveform::square: return squareValue(counter);
      case LFOWaveform::sinusoid: break;
    }
    return sineValue(counter);
  }

  static ValueType wrappedModuloCounter(ValueType counter) noexcept {
    // Fast paths for values within one cycle of the normalized range. These are the common cases -- phase increments
    // and the quad-phase offsets -- and they produce the same results as `fmod` without the library call.
    constexpr ValueType zero{0.0};
    constexpr ValueType one{1.0};
    if (counter >= zero) {
      if (counter < one) return counter;
      if (counter < ValueType{2.0}) return counter - one;
    } else if (counter > -one) {
      return wrappedNegativeCounter(counter);
    }

    if (!std::isfinite(counter)) return zero;
    counter = std::fmod(counter, one);
    return counter < zero ? wrappedNegativeCounter(counter) : counter;
  }

  /**
   Shift a value in (-1, 0) into [0, 1). For a tiny negative value, adding 1 rounds up to exactly 1, which is outside
   the normalized range; that case becomes 0, the equivalent phase.

   @param counter the value to shift
   @returns the shifted value in [0, 1)
   */
  static ValueType wrappedNegativeCounter(ValueType counter) noexcept {
    counter += ValueType{1.0};
    return counter < ValueType{1.0} ? counter : ValueType{0.0};
  }

  static ValueType sineValue(ValueType counter) noexcept {
    // Computed in `ValueType` so that float oscillators use the faster single-precision sine.
    return std::sin(ValueType{2} * std::numbers::pi_v<ValueType> * counter);
  }
  static ValueType sawtoothValue(ValueType counter) noexcept { return DSP::unipolarToBipolar(counter); }
  static ValueType triangleValue(ValueType counter) noexcept {
    return DSP::unipolarToBipolar(std::abs(DSP::unipolarToBipolar(counter)));
  }
  static ValueType squareValue(ValueType counter) noexcept {
    return counter >= ValueType{0.5} ? ValueType{1.0} : ValueType{-1.0};
  }

  LFOWaveform waveform_;
  ValueType phase_ = {0.0};
  PhaseIncrement<ValueType> phaseIncrement_;
};

} // end namespace DSPHeaders
