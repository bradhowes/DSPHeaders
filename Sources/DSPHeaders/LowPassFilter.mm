// Copyright © 2020 Brad Howes. All rights reserved.

#import <Accelerate/../Frameworks/vecLib.framework/Headers/vForce.h>

#import "DSPHeaders/ConstMath.hpp"
#import "DSPHeaders/DSP.hpp"
#import "DSPHeaders/LowPassFilter.hpp"
#import "DSPHeaders/Types.hpp"

enum Index { B0 = 0, B1, B2, A1, A2 };

void
DSPHeaders::LowPassFilter::calculateParams(double frequency, double resonance, double nyquistPeriod, size_t numChannels)
{
  if (lastFrequency_ == frequency &&
      lastResonance_ == resonance &&
      numChannels == lastNumChannels_ &&
      lastNyquistPeriod_ == nyquistPeriod) {
    return;
  }

  const double frequencyRads = ConstMath::Constants<double>::PI * frequency * nyquistPeriod;
  const double r = DSP::decibelToLinear(resonance);
  const double k  = ::sin(frequencyRads) / (r * 2.0);
  const double c1 = (1.0_F - k) / (1.0 + k);
  const double c2 = (1.0_F + c1) * ::cos(frequencyRads);
  const double c3 = (1.0_F + c1 - c2) * 0.25_F;

  F_.clear();
  F_.reserve(5 * numChannels);

  for (size_t channel = 0; channel < numChannels; ++channel) {
    F_.push_back(c3);
    F_.push_back(c3 + c3);
    F_.push_back(c3);
    F_.push_back(-c2);
    F_.push_back(c1);
  }

  // As long as we have the same number of channels, we can use Accelerate's function to update the filter.
  if (setup_ != nullptr && numChannels == lastNumChannels_) {
    float interpolationRate = float(0.0001);
    float interpolationThreshold = float(0.00001);
    vDSP_biquadm_SetTargetsDouble(setup_, F_.data(), interpolationRate, interpolationThreshold, 0, 0, 1, numChannels);
  }
  else {
    // Otherwise, we need to deallocate and create new storage for the filter definition.
    // NOTE: this should never be done from within the audio render thread.
    if (setup_ != nullptr) vDSP_biquadm_DestroySetup(setup_);
    setup_ = vDSP_biquadm_CreateSetup(F_.data(), 1, numChannels);
  }

  lastFrequency_ = frequency;
  lastResonance_ = resonance;
  lastNumChannels_ = numChannels;
}

/**
 Convert "bad" values (NaNs, very small, and very large values to 1.0. Only used below in the `magnitudes` calculations.

 - parameter x: value to check
 - returns: filtered value or 1.0
 */

void
DSPHeaders::LowPassFilter::magnitudes(AUValue const* frequencies, size_t count, double inverseNyquist, AUValue* magnitudes) const
{
  double scale = ConstMath::Constants<double>::PI * inverseNyquist;
  auto filterBadValues = [](double x) { return (::fabs(x) > 1e-15_F && ::fabs(x) < 1e15_F && x != 0.0_F) ? x : 1.0_F; };
  auto squared = [](double x) { return x * x; };

  while (count-- > 0) {
    auto theta = scale * *frequencies++;
    auto zReal = ::cos(theta);
    auto zImag = ::sin(theta);

    auto zReal2 = squared(zReal);
    auto zImag2 = squared(zImag);

    auto numerReal = F_[B0] * (zReal2 - zImag2) + F_[B1] * zReal + F_[B2];
    auto numerImag = 2.0 * F_[B0] * zReal * zImag + F_[B1] * zImag;
    auto numerMag = ::sqrt(squared(numerReal) + squared(numerImag));

    auto denomReal = zReal2 - zImag2 + F_[A1] * zReal + F_[A2];
    auto denomImag = 2.0 * zReal * zImag + F_[A1] * zImag;
    auto denomMag = ::sqrt(squared(denomReal) + squared(denomImag));

    auto value = numerMag / denomMag;
    *magnitudes++ = AUValue(20.0 * ::log10(filterBadValues(value)));
  }
}
