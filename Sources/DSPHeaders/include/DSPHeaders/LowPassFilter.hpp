// Copyright © 2025 Brad Howes. All rights reserved.

#pragma once

#import <Accelerate/Accelerate.h>
#import <cassert>
#import <cmath>
#import <vector>

#import "DSPHeaders/BusBuffers.hpp"

namespace DSPHeaders {

/**
 Implementation of a low-pass filter that uses Apple's Accelerate framework to do the biquad calculations.
 */
class LowPassFilter {
public:
  /**
   Calculate the parameters for a low-pass filter with the given frequency and resonance values.

   @param frequency the cutoff frequency for the low-pass filter
   @param resonance the resonance setting for the low-pass filter
   @param nyquistPeriod should be equivalent to 1.0 / (0.5 * sampleRate)
   @param numChannels number of channels the filter will process
   */
  void calculateParams(double frequency, double resonance, double nyquistPeriod, size_t numChannels);

  /**
   Calculate the frequency responses for the current filter configuration.

   @param frequencies array of frequency values to calculate on
   @param count the number of frequencies in the array
   @param nyquistPeriod should be equivalent to 1.0 / (0.5 * sampleRate)
   @param magnitudes mutable array of values with the same size as `frequencies` for holding the results
   */
  void magnitudes(AUValue const* frequencies, size_t count, double nyquistPeriod, AUValue* magnitudes) const;

  /**
   Apply the filter to a collection of audio samples.

   @param ins the array of samples to process
   @param outs the storage for the filtered results
   @param frameCount the number of samples to process in the sequences
   */
  void apply(BusBuffers& ins, BusBuffers& outs, size_t frameCount) const
  {
    assert(lastNumChannels_ == ins.size() && lastNumChannels_ == outs.size());
    float const* __nonnull* __nonnull input = const_cast<const AUValue**>(ins.data());
    float* __nonnull* __nonnull output = outs.data();
    vDSP_biquadm(setup_, input, one_, output, one_, vDSP_Length(frameCount));
  }

private:
  std::vector<double> F_;
  vDSP_biquadm_Setup setup_ = nullptr;
  vDSP_Stride one_{1};

  double lastFrequency_{-1.0};
  double lastResonance_{1E10};
  size_t lastNumChannels_{0};
};

} // end namespace DSPHeaders
