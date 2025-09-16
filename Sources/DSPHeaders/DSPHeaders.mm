// Copyright © 2022-2025 Brad Howes. All rights reserved.

#include "DSPHeaders/DSP.hpp"

using namespace DSPHeaders;
using namespace DSPHeaders::DSP;

static constexpr size_t TableSize = Interpolation::Cubic4thOrder::TableSize;

static constexpr double x1(size_t index) { return double(index) / double(TableSize); }
static constexpr double x2(double x1) { return x1 * x1; }
static constexpr double x3(double x1, double x2) { return x1 * x2; }

static constexpr double w0(size_t index) {
  auto x1_ = x1(index);
  auto x2_ = x2(x1_);
  auto x3_ = x3(x1_, x2_);
  auto x_05 = 0.5 * x1_;
  auto x3_05 = 0.5 * x3_;
  return -x3_05 + x2_ - x_05;
}

static constexpr double w1(size_t index) {
  auto x1_ = x1(index);
  auto x2_ = x2(x1_);
  auto x3_ = x3(x1_, x2_);
  auto x3_15 = 1.5 * x3_;
  return x3_15 - 2.5 * x2_ + 1.0;
}

static constexpr double w2(size_t index) {
  auto x1_ = x1(index);
  auto x2_ = x2(x1_);
  auto x3_ = x3(x1_, x2_);
  auto x_05 = 0.5 * x1_;
  auto x3_15 = 1.5 * x3_;
  return -x3_15 + 2.0 * x2_ + x_05;
}

static constexpr double w3(size_t index) {
  auto x1_ = x1(index);
  auto x2_ = x2(x1_);
  auto x3_ = x3(x1_, x2_);
  auto x3_05 = 0.5 * x3_;
  return x3_05 - 0.5 * x2_;
}

Interpolation::Cubic4thOrder::WeightsEntry DSPHeaders::DSP::Interpolation::Cubic4thOrder::generator(size_t index) {
  return {w0(index), w1(index), w2(index), w3(index)};
}

std::array<Interpolation::Cubic4thOrder::WeightsEntry, TableSize> Interpolation::Cubic4thOrder::weights_ =
  ConstMath::make_array<Interpolation::Cubic4thOrder::WeightsEntry, TableSize>(generator);
