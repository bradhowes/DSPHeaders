// Copyright © 2025 Brad Howes. All rights reserved.

#pragma once

#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <cmath>
#include <vector>

#include "DSPHeaders/BusBuffers.hpp"

namespace DSPHeaders {

/**
 Implementation of a low-pass filter that uses Apple's Accelerate framework to do the biquad calculations. Suitable for
 multi-channel processing of a sequence of samples. For sample-based filter, use the ``Biquad::Filter`` with a suitable
 transform and use the ``Coefficients::LPF2`` to initialize the filter parameters.
 */
class LowPassFilter {
public:
  LowPassFilter() = default;
  ~LowPassFilter() noexcept;

  LowPassFilter(const LowPassFilter&) = delete;
  LowPassFilter(LowPassFilter&&) = delete;
  LowPassFilter& operator=(const LowPassFilter&) = delete;
  LowPassFilter& operator=(LowPassFilter&&) = delete;

  /**
   Calculate the parameters for a low-pass filter with the given frequency and resonance values.

   @param frequency the cutoff frequency for the low-pass filter
   @param resonance the resonance setting for the low-pass filter in range -20dB and +40dB
   @param nyquistPeriod should be equivalent to 2.0 / sampleRate
   @param numChannels number of channels the filter will process
   */
  void calculateParams(double frequency, double resonance, double nyquistPeriod, size_t numChannels);

  /**
   Calculate the frequency responses for the current filter configuration. Before `calculateParams` has configured the
   filter, it does not filter, so every magnitude is 0 dB.

   @param frequencies array of frequency values to calculate on
   @param count the number of frequencies in the array
   @param nyquistPeriod should be equivalent to 1.0 / (0.5 * sampleRate)
   @param magnitudes mutable array of values with the same size as `frequencies` for holding the results
   */
  void magnitudes(AUValue const* frequencies, size_t count, double nyquistPeriod, AUValue* magnitudes) const;

  /**
   Apply the filter to a collection of audio samples. If the filter has not been configured by `calculateParams`, or
   was configured for a different number of channels than `ins` or `outs` holds, the samples are passed through
   unfiltered rather than handing Accelerate a missing setup or too few channel buffers.

   @param ins the array of samples to process
   @param outs the storage for the filtered results
   @param frameCount the number of samples to process in the sequences
   */
  void apply(const BusBuffers& ins, BusBuffers& outs, size_t frameCount) const
  {
    if (setup_ == nullptr || lastNumChannels_ != ins.size() || lastNumChannels_ != outs.size()) [[unlikely]] {
      passThrough(ins, outs, frameCount);
      return;
    }
    float const* __nonnull* __nonnull input = const_cast<const AUValue**>(ins.data());
    float* __nonnull* __nonnull output = outs.data();
    vDSP_biquadm(setup_, input, one_, output, one_, vDSP_Length(frameCount));
  }

private:

  /// Copy each input channel to the matching output channel, skipping missing and shared (in-place) buffers.
  static void passThrough(const BusBuffers& ins, BusBuffers& outs, size_t frameCount) noexcept {
    for (size_t channel = 0; channel < std::min(ins.size(), outs.size()); ++channel) {
      const AUValue* in = ins[channel];
      AUValue* out = outs[channel];
      if (in != nullptr && out != nullptr && in != out) std::copy_n(in, frameCount, out);
    }
  }

  std::vector<double> F_;
  vDSP_biquadm_Setup setup_ = nullptr;
  vDSP_Stride one_{1};

  double lastFrequency_{-1.0};
  double lastResonance_{1E10};
  double lastNyquistPeriod_{0};
  size_t lastNumChannels_{0};
};

} // end namespace DSPHeaders
