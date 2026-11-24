// Copyright © 2021-2024 Brad Howes. All rights reserved.

#import <XCTest/XCTest.h>
#import <algorithm>
#import <cmath>
#import <iomanip>
#import <iostream>
#import <limits>
#import <vector>

#import "DSPHeaders/DelayBuffer.hpp"

using namespace DSPHeaders;

@interface DelayBufferTests : XCTestCase
@end

@implementation DelayBufferTests

static float epsilon = 1.0E-7;

- (void)setUp {}

- (void)tearDown {}

- (void)testSizing {
  XCTAssertEqual(1, DelayBuffer<float>(-1.0).size());
  XCTAssertEqual(2, DelayBuffer<float>(1.2).size());
  XCTAssertEqual(32, DelayBuffer<float>(32.0).size());
  XCTAssertEqual(128, DelayBuffer<float>(123.4).size());
  XCTAssertEqual(1024, DelayBuffer<float>(1024.0).size());
}

- (void)testReadFromOffset{
  auto buffer = DelayBuffer<float>(4);
  XCTAssertEqual(4, buffer.size());
  buffer.write(1.2);
  buffer.write(2.4);
  buffer.write(3.6);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(0), 3.6, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(1), 2.4, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(2), 1.2, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(3), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(4), 3.6, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(5), 2.4, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(6), 1.2, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(7), 0.0, epsilon);

  XCTAssertEqualWithAccuracy(buffer.readFromOffset(-1), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(-2), 1.2, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(-3), 2.4, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(-4), 3.6, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(-5), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(-6), 1.2, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(-7), 2.4, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(-8), 3.6, epsilon);
}

- (void)testInterpolatorSelection {
  static_assert(DelayBuffer<float>::interpolator == DelayBufferInterpolator::linear);
  static_assert(DelayBuffer<float, DelayBufferInterpolator::cubic4thOrder>::interpolator ==
                DelayBuffer<float>::Interpolator::cubic4thOrder);

  // At a fractional delay the two interpolators give different results from the same samples.
  DelayBuffer<double> linear(8);
  DelayBuffer<double, DelayBufferInterpolator::cubic4thOrder> cubic(8);
  for (double value : {0.0, 0.25, 0.5, 0.75, 1.0, 0.75, 0.5, 0.25}) {
    linear.write(value);
    cubic.write(value);
  }
  XCTAssertEqualWithAccuracy(linear.read(2.5), 0.875, epsilon);
  XCTAssertEqualWithAccuracy(cubic.read(2.5), 0.90625, epsilon);
}

- (void)testWriteWrapping {
  auto buffer = DelayBuffer<double, DelayBufferInterpolator::linear>(4);
  XCTAssertEqual(4, buffer.size());
  buffer.write(1.2);
  buffer.write(2.4);
  buffer.write(3.6);
  buffer.write(4.8);
  buffer.write(5.0);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(0), 5.0, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(1), 4.8, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(2), 3.6, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(3), 2.4, epsilon);
  XCTAssertEqualWithAccuracy(buffer.readFromOffset(4), 5.0, epsilon);
}

- (void)testReadLinearInterpolated {
  auto buffer = DelayBuffer<double, DelayBufferInterpolator::linear>(8);
  XCTAssertEqual(8, buffer.size());
  buffer.write(1.2);
  buffer.write(2.4);
  buffer.write(3.6);
  XCTAssertEqualWithAccuracy(buffer.read(0.0), 3.60, epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(0.5), 3.00, epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(1.0), 2.40, epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(2.0), 1.20, epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(3.0), 0.00, epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(1.1), 2.28, epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(1.2), 2.16, epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(1.5), 1.80, epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(1.8), 1.44, epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(1.9), 1.32, epsilon);
}

- (void)testReadCubic4thOrderInterpolated {
  auto buffer = DelayBuffer<double, DelayBufferInterpolator::cubic4thOrder>(8);
  XCTAssertEqual(8, buffer.size());
  buffer.write(0.00);
  buffer.write(0.25);
  buffer.write(0.50);
  buffer.write(0.75);
  buffer.write(1.00);
  buffer.write(0.75);
  buffer.write(0.50);
  buffer.write(0.25);
  // Offsets 0..7 now hold 0.25, 0.5, 0.75, 1.0, 0.75, 0.5, 0.25, 0.0.
  XCTAssertEqualWithAccuracy(buffer.read(0.0), 0.250, epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(1.0), 0.500, epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(2.0), 0.750, epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(3.0), 1.000, epsilon);

  // Under one sample there is no newer sample, so the newest is repeated: weights at 0.5 are
  // (-0.0625, 0.5625, 0.5625, -0.0625) over (0.25, 0.25, 0.5, 0.75).
  XCTAssertEqualWithAccuracy(buffer.read(0.5), 0.359375, epsilon);

  // Offsets 0..3 lie on a line rising 0.25 per sample, which Catmull-Rom reproduces exactly, so these are
  // 0.5 + 0.25 * t where the weights table rounds t down to a multiple of 1/1024.
  XCTAssertEqualWithAccuracy(buffer.read(1.1), 0.5 + 0.25 * (102.0 / 1024.0), epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(1.2), 0.5 + 0.25 * (204.0 / 1024.0), epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(1.5), 0.625, epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(1.8), 0.5 + 0.25 * (819.0 / 1024.0), epsilon);
  XCTAssertEqualWithAccuracy(buffer.read(1.9), 0.5 + 0.25 * (921.0 / 1024.0), epsilon);

  // Around the peak the curve rises above the straight line between 0.75 and 1.0.
  XCTAssertEqualWithAccuracy(buffer.read(2.5), 0.90625, epsilon);
}

- (void)testCubicMatchesSignalAndIsContinuous {
  // Fill the buffer with a slow sine so the true value at any fractional delay is known.
  constexpr int count = 64;
  constexpr double samplesPerCycle = 32.0;
  auto signal = [&](double n) { return std::sin(2.0 * M_PI * n / samplesPerCycle); };
  DelayBuffer<double, DelayBufferInterpolator::cubic4thOrder> cubic(count);
  DelayBuffer<double> linear(count);
  for (int n = 0; n < count; ++n) {
    cubic.write(signal(n));
    linear.write(signal(n));
  }

  // Offset k holds sample n = count - 1 - k. Cubic must track the signal and be more accurate than linear.
  double cubicError = 0.0, linearError = 0.0;
  for (int step = 40; step <= 400; ++step) {
    double delay = step / 40.0;
    double expected = signal(count - 1 - delay);
    cubicError = std::max(cubicError, std::fabs(cubic.read(delay) - expected));
    linearError = std::max(linearError, std::fabs(linear.read(delay) - expected));
  }
  XCTAssertLessThan(cubicError, 5.0e-4);
  XCTAssertLessThan(cubicError, linearError / 10.0);

  // No jump when a sweeping delay crosses a whole number of samples.
  for (int whole = 1; whole < 10; ++whole) {
    XCTAssertEqualWithAccuracy(cubic.read(double(whole)), cubic.read(whole + 1.0e-9), 1.0e-6, @"whole: %d", whole);
  }
}

- (void)testReadClampsDelayToBuffer {
  // Offset k holds the value 8 - k, so the oldest sample (offset 7) is 1 and the newest (offset 0) is 8.
  DelayBuffer<float> linear(8);
  DelayBuffer<float, DelayBufferInterpolator::cubic4thOrder> cubic(8);
  for (int value = 1; value <= 8; ++value) {
    linear.write(float(value));
    cubic.write(float(value));
  }

  // Linear reads one sample past the whole delay and cubic two, so their limits differ.
  XCTAssertEqual(linear.maxDelay(), 7.0f);
  XCTAssertEqual(cubic.maxDelay(), 6.0f);

  // Negative and NaN delays read the newest sample instead of outside the buffer or the weights table.
  const float nan = std::numeric_limits<float>::quiet_NaN();
  for (float delay : {-0.5f, -3.0f, -1.0e9f, nan}) {
    XCTAssertEqual(linear.read(delay), 8.0f, @"delay: %f", delay);
    XCTAssertEqual(cubic.read(delay), 8.0f, @"delay: %f", delay);
  }

  // Delays past the end read the oldest usable sample instead of wrapping around to recent ones.
  for (float delay : {7.5f, 8.0f, 100.0f, std::numeric_limits<float>::infinity()}) {
    XCTAssertEqual(linear.read(delay), 1.0f, @"delay: %f", delay);
    XCTAssertEqual(cubic.read(delay), 2.0f, @"delay: %f", delay);
  }

  // Delays inside the range are unchanged.
  XCTAssertEqualWithAccuracy(linear.read(6.5f), 1.5f, 1.0e-6f);
  XCTAssertEqual(linear.read(7.0f), 1.0f);
  XCTAssertEqual(cubic.read(6.0f), 2.0f);
}

@end
