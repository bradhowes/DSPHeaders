// Copyright © 2021-2026 Brad Howes. All rights reserved.

#pragma once

#include <cmath>
#include <vector>

#include "DSPHeaders/DSP.hpp"

namespace DSPHeaders {

/// Types of interpolation that can be used to generate sample values using floating-point indices.
enum struct DelayBufferInterpolator {
  linear,
  cubic4thOrder
};

/**
 Circular buffer that holds a maximum number of samples. It manages a write position which is where new samples are
 added to the buffer. Reading takes place some samples before the current write position with interpolation
 being used to generate the sample value. This only works as long as each sample is written at a fixed sample rate so
 that a delay in seconds can be calculated as N number of samples in the past.

 The interpolation is chosen at compile time by the `InterpolatorKind` template parameter so that `read` calls the
 interpolator directly and the compiler can inline it.

 This buffer is not thread-safe. It is to be used in the rendering flow of one channel of audio.
 */
template <typename ValueType, DelayBufferInterpolator InterpolatorKind = DelayBufferInterpolator::linear>
class DelayBuffer {
public:
  /// Alias so that `DelayBuffer<T>::Interpolator::linear` continues to name the interpolation kinds.
  using Interpolator = DelayBufferInterpolator;

  /// The interpolation applied by `read`.
  static constexpr Interpolator interpolator = InterpolatorKind;

  /**
   Construct new buffer that can hold given number of samples.

   @param sizeInSamples capacity of the buffer
   */
  DelayBuffer(double sizeInSamples) noexcept :
  buffer_(smallestPowerOf2For(sizeInSamples), ValueType{0.0}), writePos_{0}, wrapMask_{buffer_.size() - 1} {}

  /**
   Wipe the buffer contents by filling it with zeros.
   */
  void clear() noexcept { std::fill(buffer_.begin(), buffer_.end(), ValueType{0.0}); }

  /**
   Write a sample to the end of the buffer, advancing the write position to the next location.

   @param value the sample to add
   */
  void write(ValueType value) noexcept {
    buffer_[writePos_] = value;
    writePos_ = (writePos_ + 1) & wrapMask_;
  }

  /**
   Physical size of the buffer. This is always a power of 2 and may not match the value given in the constructor or the
   last `setSizeInSamples` call.

   @return buffer size
   */
  size_t size() const noexcept { return buffer_.size(); }

  /**
   Obtain a sample from the buffer.

   @param offset how many samples before the current write position to return
   @return sample from buffer
   */
  ValueType readFromOffset(ssize_t offset) const noexcept {
    return buffer_[size_t(writePos_ - 1 - offset) & wrapMask_];
  }

  /**
   The largest delay that `read` supports. The interpolators read samples beyond the whole part of the delay (one more
   for linear, two more for cubic), and those samples must still be in the buffer.

   @returns the maximum delay in samples
   */
  ValueType maxDelay() const noexcept {
    return ValueType(buffer_.size() - (InterpolatorKind == Interpolator::cubic4thOrder ? 2 : 1));
  }

  /**
   Obtain a sample from the buffer using the interpolation method chosen by the `InterpolatorKind` template parameter.
   The delay is clamped to [0, `maxDelay()`], and a NaN delay is treated as 0, so that no delay value reads outside
   the buffer or the interpolation table.

   @param delay distance from the current write position to return
   @return interpolated sample from buffer
   */
  ValueType read(ValueType delay) const noexcept {
    // Written so that NaN fails the first comparison and becomes 0; `std::clamp` would pass NaN through.
    if (!(delay > ValueType{0})) [[unlikely]] {
      delay = ValueType{0};
    } else if (delay > maxDelay()) [[unlikely]] {
      delay = maxDelay();
    }

    // Convert delay distance into whole and partial components.
    auto offset = int(delay);
    if constexpr (InterpolatorKind == Interpolator::cubic4thOrder) {
      return cubic4thOrderInterpolate(offset, delay - offset);
    } else {
      return linearInterpolate(offset, delay - offset);
    }
  }

private:
  static size_t smallestPowerOf2For(double value) noexcept {
    return size_t(std::pow(2.0, std::ceil(std::log2(std::fmax(value, 1.0)))));
  }

  /**
   Obtain a linearly interpolated sample for a given index value.

   @param whole the index of the first sample to use
   @param partial the non-integral part of the index
   @returns interpolated sample result
   */
  ValueType linearInterpolate(ssize_t whole, ValueType partial) const noexcept {
    return (partial == 0.0) ? readFromOffset(whole) : DSP::Interpolation::linear(partial,
                                                                                 readFromOffset(whole),
                                                                                 readFromOffset(whole + 1));
  }

  /**
   Obtain a cubic 4th-order interpolated sample for a given index value. The interpolator works on four samples and
   produces a value between the second and third, so it is given the samples one newer than `whole` through two
   older, and interpolates between `whole` and `whole + 1` just like `linearInterpolate`.

   @param whole the index of the first sample to use
   @param partial the non-integral part of the index
   @returns interpolated sample result
   */
  ValueType cubic4thOrderInterpolate(ssize_t whole, ValueType partial) const noexcept {
    if (partial == 0.0) return readFromOffset(whole);
    // For a delay under one sample there is no newer sample, so repeat the newest one.
    ValueType newer = whole > 0 ? readFromOffset(whole - 1) : readFromOffset(whole);
    return DSP::Interpolation::cubic4thOrder(partial, newer, readFromOffset(whole), readFromOffset(whole + 1),
                                             readFromOffset(whole + 2));
  }

  std::vector<ValueType> buffer_;
  size_t writePos_;
  size_t wrapMask_;
};

} // end namespace DSPHeaders
