// Copyright © 2021-2024 Brad Howes. All rights reserved.

#import <XCTest/XCTest.h>
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
  filter.calculateParams(8000.0, 0.6, nyquistPeriod, 2);
  filter.calculateParams(8001.0, 0.6, nyquistPeriod, 2);
  filter.calculateParams(8001.0, 0.6, nyquistPeriod, 2);
  filter.calculateParams(8001.0, 0.6, nyquistPeriod, 1);
}

@end
