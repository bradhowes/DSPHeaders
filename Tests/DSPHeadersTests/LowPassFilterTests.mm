// Copyright © 2021-2024 Brad Howes. All rights reserved.

#import <XCTest/XCTest.h>
#import <type_traits>
#import <vector>

#import "DSPHeaders/LowPassFilter.hpp"

using namespace DSPHeaders;

#define SamplesEqual(A, B) XCTAssertEqualWithAccuracy(A, B, self.epsilon)

@interface LowPassFilterTests : XCTestCase
@property float epsilon;
@end

@implementation LowPassFilterTests

- (void)setUp {
  _epsilon = 1.0e-6;
}

- (void)testMagnatudes {
  LowPassFilter filter;
  double nyquistPeriod = 1.0 / (44100.0 / 2);
  filter.calculateParams(8000.0, 0.5, nyquistPeriod, 2);
  const AUValue freqs[] = {100, 200, 300, 400, 500};
  AUValue mags[] = {0, 0, 0, 0, 0};
  filter.magnitudes(freqs, 5, nyquistPeriod, mags);
  SamplesEqual(mags[0], 0.000595);
  SamplesEqual(mags[1], 0.002380);
  SamplesEqual(mags[2], 0.005355);
  SamplesEqual(mags[3], 0.009519);
  SamplesEqual(mags[4], 0.014873);
}

- (void)testApply {
  LowPassFilter filter;
  double nyquistPeriod = 1.0 / (44100.0 / 2);
  filter.calculateParams(8000.0, 0.5, nyquistPeriod, 2);

  AUValue inLeft[] = {0, 0, 0, 0, 0};
  AUValue inRight[] = {0, 0, 0, 0, 0};
  std::vector<AUValue*> inBufs{inLeft, inRight};
  DSPHeaders::BusBuffers ins(inBufs);

  AUValue outLeft[] = {0, 0, 0, 0, 0};
  AUValue outRight[] = {0, 0, 0, 0, 0};
  std::vector<AUValue*> outBufs{outLeft, outRight};
  DSPHeaders::BusBuffers outs(outBufs);

  const AUValue freqs[] = {100, 200, 300, 400, 500};
  AUValue mags[] = {0, 0, 0, 0, 0};
  filter.apply(ins, outs, 5);

  SamplesEqual(outLeft[0], 0.0);
  SamplesEqual(outLeft[1], 0.0);
  SamplesEqual(outLeft[2], 0.0);
  SamplesEqual(outLeft[3], 0.0);
  SamplesEqual(outLeft[4], 0.0);

  SamplesEqual(outRight[0], 0.0);
  SamplesEqual(outRight[1], 0.0);
  SamplesEqual(outRight[2], 0.0);
  SamplesEqual(outRight[3], 0.0);
  SamplesEqual(outRight[4], 0.0);

  inLeft[0] = 1.0;
  inLeft[1] = -1.0;
  inLeft[2] = 1.0;
  inLeft[3] = -1.0;
  inLeft[4] = 1.0;

  inRight[0] = -1.0;
  inRight[1] =  0.0;
  inRight[2] =  1.0;
  inRight[3] =  0.0;
  inRight[4] = -1.0;

  filter.apply(ins, outs, 5);

  SamplesEqual(outLeft[0],  0.203739);
  SamplesEqual(outLeft[1],  0.322877);
  SamplesEqual(outLeft[2],  0.107368);
  SamplesEqual(outLeft[3], -0.066274);
  SamplesEqual(outLeft[4], -0.081670);

  SamplesEqual(outRight[0], -0.203739);
  SamplesEqual(outRight[1], -0.526615);
  SamplesEqual(outRight[2], -0.226505);
  SamplesEqual(outRight[3],  0.485521);
  SamplesEqual(outRight[4],  0.374450);
}

- (void)testCalculateParams {
  LowPassFilter filter;
  double nyquistPeriod = 1.0 / (44100.0 / 2);
  filter.calculateParams(8000.0, 0.5, nyquistPeriod, 2);
  filter.calculateParams(8000.0, 0.5, nyquistPeriod, 2);
  filter.calculateParams(8000.0, 0.6, nyquistPeriod, 2);
  filter.calculateParams(8001.0, 0.6, nyquistPeriod, 2);
  filter.calculateParams(8001.0, 0.6, nyquistPeriod, 2);
  filter.calculateParams(8001.0, 0.6, nyquistPeriod, 1);
}

- (void)testUnconfiguredFilterPassesThrough {
  LowPassFilter filter;

  // Without coefficients the response is flat at 0 dB.
  double nyquistPeriod = 1.0 / (44100.0 / 2);
  const AUValue freqs[] = {100, 1000, 10000};
  AUValue mags[] = {-1, -1, -1};
  filter.magnitudes(freqs, 3, nyquistPeriod, mags);
  XCTAssertEqual(mags[0], 0.0f);
  XCTAssertEqual(mags[1], 0.0f);
  XCTAssertEqual(mags[2], 0.0f);

  // Without a vDSP setup the samples are copied unchanged.
  AUValue inLeft[] = {1, -1, 0.5}, inRight[] = {0.25, 0, -0.25};
  std::vector<AUValue*> inBufs{inLeft, inRight};
  BusBuffers ins(inBufs);
  AUValue outLeft[] = {9, 9, 9}, outRight[] = {9, 9, 9};
  std::vector<AUValue*> outBufs{outLeft, outRight};
  BusBuffers outs(outBufs);
  filter.apply(ins, outs, 3);
  for (int frame = 0; frame < 3; ++frame) {
    XCTAssertEqual(outLeft[frame], inLeft[frame]);
    XCTAssertEqual(outRight[frame], inRight[frame]);
  }
}

- (void)testChannelCountMismatchPassesThrough {
  // Configured for one channel but given two: vDSP must not be handed more channel buffers than it was set up for,
  // or fewer.
  LowPassFilter filter;
  double nyquistPeriod = 1.0 / (44100.0 / 2);
  filter.calculateParams(8000.0, 0.5, nyquistPeriod, 1);

  AUValue inLeft[] = {1, -1, 1}, inRight[] = {-1, 0, 1};
  std::vector<AUValue*> inBufs{inLeft, inRight};
  BusBuffers ins(inBufs);
  AUValue outLeft[] = {9, 9, 9}, outRight[] = {9, 9, 9};
  std::vector<AUValue*> outBufs{outLeft, outRight};
  BusBuffers outs(outBufs);
  filter.apply(ins, outs, 3);
  for (int frame = 0; frame < 3; ++frame) {
    XCTAssertEqual(outLeft[frame], inLeft[frame]);
    XCTAssertEqual(outRight[frame], inRight[frame]);
  }

  // In-place buffers are left alone.
  filter.apply(ins, ins, 3);
  XCTAssertEqual(inLeft[1], -1.0f);
}

- (void)testExclusiveSetupOwnership {
  XCTAssertFalse((std::is_copy_constructible_v<LowPassFilter>));
  XCTAssertFalse((std::is_copy_assignable_v<LowPassFilter>));
  XCTAssertFalse((std::is_move_constructible_v<LowPassFilter>));
  XCTAssertFalse((std::is_move_assignable_v<LowPassFilter>));
}

@end
