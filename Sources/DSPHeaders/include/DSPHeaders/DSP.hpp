// Copyright © 2021-2025 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <concepts>
#include <type_traits>

#include "DSPHeaders/ConstMath.hpp"

// NOTE: the routines below compute in `ValueType` so that float code is not silently promoted to double.

namespace DSPHeaders::DSP {

template <std::floating_point ValueType>
constexpr ValueType decibelToLinear(ValueType decibels) noexcept {
  return std::pow(ValueType{10.0}, decibels / ValueType{20.0});
}

/**
 Translate value in range [0, +1] into one in range [-1, +1]

 @param value the value to translate
 @returns value in range [-1, +1]
 */
template <std::floating_point ValueType>
constexpr ValueType unipolarToBipolar(ValueType value) noexcept { return ValueType{2.0} * value - ValueType{1.0}; }

/**
 Translate value in range [-1, +1] into one in range [0, +1]

 @param value the value to translate
 @returns value in range [0, +1]
 */
template <std::floating_point ValueType>
constexpr ValueType bipolarToUnipolar(ValueType value) noexcept { return ValueType{0.5} * value + ValueType{0.5}; }

/**
 Perform linear translation from a value in range [0.0, 1.0] into one in [minValue, maxValue].

 @param value the value to translate
 @param minValue the lowest value to return when modulator is 0
 @param maxValue the highest value to return when modulator is +1
 @returns value in range [minValue, maxValue]
 */
template <std::floating_point ValueType>
constexpr ValueType unipolarModulation(ValueType value, ValueType minValue, ValueType maxValue) noexcept {
  return std::clamp<ValueType>(value, 0.0, 1.0) * (maxValue - minValue) + minValue;
}

/**
 Perform linear translation from a value in range [-1.0, 1.0] into one in [minValue, maxValue]

 @param value the value to translate
 @param minValue the lowest value to return when modulator is -1
 @param maxValue the highest value to return when modulator is +1
 @returns value in range [minValue, maxValue]
 */
template <std::floating_point ValueType>
constexpr ValueType bipolarModulation(ValueType value, ValueType minValue, ValueType maxValue) noexcept {
  auto mid = (maxValue - minValue) * ValueType{0.5};
  return std::clamp<ValueType>(value, -1.0, 1.0) * mid + mid + minValue;
}

namespace Interpolation {

/**
 Interpolate a value from two values.

 @param partial indication of affinity for one of the two values. Values [0-0.5) favor x0, while values (0.5-1.0)
 favor x1. A value of 0.5 equally favors both.
 @param x0 first value to use
 @param x1 second value to use

 The computation type comes from `partial`; the sample values are converted to it.
 */
template <std::floating_point ValueType>
inline constexpr ValueType linear(ValueType partial, std::type_identity_t<ValueType> x0,
                                  std::type_identity_t<ValueType> x1) noexcept {
  return partial * (x1 - x0) + x0;
}

/**
 Types and configuration for the cubic 4th order interpolator. The weights table is generated at compile time, one per
 `ValueType`, so that interpolation reads weights of the same type as the samples it combines.
 */
template <std::floating_point ValueType>
struct Cubic4thOrder {
  static constexpr size_t TableSize = 1024;
  using WeightsEntry = std::array<ValueType, 4>;

  /**
   Generate the weights for one table entry. The weights are calculated in double precision and then rounded to
   `ValueType`, so a float table holds the nearest float to each double weight.

   @param index the table entry to generate, in [0, TableSize)
   @returns the four weights for the entry
   */
  static constexpr WeightsEntry generator(size_t index) noexcept {
    double x1 = double(index) / double(TableSize);
    double x2 = x1 * x1;
    double x3 = x1 * x2;
    return {
      ValueType(-0.5 * x3 + x2 - 0.5 * x1),
      ValueType(1.5 * x3 - 2.5 * x2 + 1.0),
      ValueType(-1.5 * x3 + 2.0 * x2 + 0.5 * x1),
      ValueType(0.5 * x3 - 0.5 * x2)
    };
  }

  static constexpr std::array<WeightsEntry, TableSize> weights_ =
    ConstMath::make_array<WeightsEntry, TableSize>(generator);
};

/**
 Interpolate a value from four values.

 @param partial location between the first value and the second. By definition it should always be < 1.0
 @param x0 first value to use
 @param x1 second value to use
 @param x2 third value to use
 @param x3 fourth value to use

 The computation type comes from `partial`; the sample values are converted to it.
 */
template <std::floating_point ValueType>
inline constexpr ValueType cubic4thOrder(ValueType partial, std::type_identity_t<ValueType> x0,
                                         std::type_identity_t<ValueType> x1, std::type_identity_t<ValueType> x2,
                                         std::type_identity_t<ValueType> x3) noexcept {
  // Partial is expected to be < 1.0 so with truncation index should always be in range [0, 1)
  using Table = Cubic4thOrder<ValueType>;
  size_t index = size_t(partial * ValueType(Table::TableSize));
  assert(index < Table::TableSize);
  const auto& w{Table::weights_[index]};
  return x0 * w[0] + x1 * w[1] + x2 * w[2] + x3 * w[3];
}

} // Interpolation namespace

} // end namespace DSPHeaders::DSP
