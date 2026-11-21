// Copyright © 2021-2024 Brad Howes. All rights reserved.

#import <XCTest/XCTest.h>
#import <cmath>
#import <limits>
#import <numbers>
#import <vector>

#import "DSPHeaders/LFO.hpp"

using namespace DSPHeaders;

#define SamplesEqual(A, B) XCTAssertEqualWithAccuracy(A, B, _epsilon)

@interface LFOTests : XCTestCase
@property float epsilon;
@end

@implementation LFOTests

- (void)setUp {
  _epsilon = 0.0001;
}

- (void)tearDown {
  // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testSinusoidSamples {
  AUValue sampleRate{4.0};
  Parameters::Float freq{1, 1.0};
  LFO<AUValue> osc(freq, sampleRate, LFOWaveform::sinusoid);
  XCTAssertEqual(LFOWaveform::sinusoid, osc.waveform());

  SamplesEqual(osc.value(),  0.0);
  osc.increment();
  SamplesEqual(osc.value(),  1.0);
  osc.increment();
  SamplesEqual(osc.value(),  0.0);
  osc.increment();
  SamplesEqual(osc.value(), -1.0);
  osc.increment();
  SamplesEqual(osc.value(),  0.0);
  osc.increment();
  SamplesEqual(osc.value(),  1.0);
  osc.increment();
  SamplesEqual(osc.value(),  0.0);
  osc.increment();
  SamplesEqual(osc.value(), -1.0);
}

- (void)testSawtoothSamples {
  Parameters::Float freq{1, 1.0};
  LFO<float> osc(freq, 8.0, LFOWaveform::sawtooth);
  XCTAssertEqual(LFOWaveform::sawtooth, osc.waveform());

  SamplesEqual(osc.value(), -1.00);
  osc.increment();
  SamplesEqual(osc.value(), -0.75);
  osc.increment();
  SamplesEqual(osc.value(), -0.50);
  osc.increment();
  SamplesEqual(osc.value(), -0.25);
  osc.increment();
  SamplesEqual(osc.value(),  0.00);
  osc.increment();
  SamplesEqual(osc.value(),  0.25);
  osc.increment();
  SamplesEqual(osc.value(),  0.50);
  osc.increment();
  SamplesEqual(osc.value(),  0.75);
  osc.increment();
  SamplesEqual(osc.value(), -1.00);
}

- (void)testTriangleSamples {
  Parameters::Float freq{1, 1.0};
  LFO<float> osc(freq, 8.0, LFOWaveform::triangle);
  XCTAssertEqual(LFOWaveform::triangle, osc.waveform());

  SamplesEqual(osc.value(),  1.0);
  osc.increment();
  SamplesEqual(osc.value(),  0.5);
  osc.increment();
  SamplesEqual(osc.value(),  0.0);
  osc.increment();
  SamplesEqual(osc.value(), -0.5);
  osc.increment();
  SamplesEqual(osc.value(), -1.0);
  osc.increment();
  SamplesEqual(osc.value(), -0.5);
  osc.increment();
  SamplesEqual(osc.value(),  0.0);
  osc.increment();
  SamplesEqual(osc.value(),  0.5);
  osc.increment();
  SamplesEqual(osc.value(),  1.0);
}

- (void)testQuadPhaseSamples {
  Parameters::Float freq{1, 1.0};
  LFO<float> osc(freq, 8.0, LFOWaveform::sawtooth);
  XCTAssertEqual(LFOWaveform::sawtooth, osc.waveform());

  SamplesEqual(osc.value(), -1.00);
  osc.increment();
  SamplesEqual(osc.quadPhaseValue(), -0.250);
  SamplesEqual(osc.quadPhaseValue(), -0.250);
  SamplesEqual(osc.value(), -0.75);
  osc.increment();
  SamplesEqual(osc.quadPhaseValue(),  0.00);
  SamplesEqual(osc.value(), -0.50);
  osc.increment();
  SamplesEqual(osc.quadPhaseValue(),  0.25);
  SamplesEqual(osc.value(), -0.25);
  osc.increment();
  SamplesEqual(osc.quadPhaseValue(),  0.50);
  SamplesEqual(osc.value(),  0.00);
  osc.increment();
  SamplesEqual(osc.quadPhaseValue(),  0.75);
  SamplesEqual(osc.value(),  0.25);
  osc.increment();
  SamplesEqual(osc.quadPhaseValue(), -1.00);
  SamplesEqual(osc.value(),  0.50);
  osc.increment();
  SamplesEqual(osc.quadPhaseValue(), -0.75);
  SamplesEqual(osc.value(),  0.75);
  osc.increment();
  SamplesEqual(osc.quadPhaseValue(), -0.50);
  SamplesEqual(osc.value(), -1.00);
  osc.increment();
  SamplesEqual(osc.quadPhaseValue(), -0.25);
}

- (void)testSquareSamples {
  Parameters::Float freq{1, 1.0};
  LFO<float> osc(freq, 8.0, LFOWaveform::square);
  XCTAssertEqual(LFOWaveform::square, osc.waveform());

  SamplesEqual(osc.value(), -1.0);
  osc.increment();
  SamplesEqual(osc.value(), -1.0);
  osc.increment();
  SamplesEqual(osc.value(), -1.0);
  osc.increment();
  SamplesEqual(osc.value(), -1.0);
  osc.increment();
  SamplesEqual(osc.value(),  1.0);
  osc.increment();
  SamplesEqual(osc.value(),  1.0);
  osc.increment();
  SamplesEqual(osc.value(),  1.0);
  osc.increment();
  SamplesEqual(osc.value(),  1.0);
  osc.increment();
  SamplesEqual(osc.value(), -1.0);
}

- (void)testInContainer {
  std::vector<LFO<float>> lfos;
  // lfos.emplace_back(44100.0, 12.0, LFOWaveform::sinusoid);
}

- (void)testSetSinePhase {
  Parameters::Float freq{1, 1.0};
  LFO<float> osc(freq, 4.0, LFOWaveform::sinusoid);
  SamplesEqual(osc.value(),  0.0);
  osc.setPhase(0.25);
  SamplesEqual(osc.value(),  1.0);
  osc.setPhase(0.50);
  SamplesEqual(osc.value(),  0.0);
  osc.setPhase(0.75);
  SamplesEqual(osc.value(), -1.0);
}

- (void)testSetSawtoothPhase {
  Parameters::Float freq{1, 1.0};
  LFO<float> osc(freq, 4.0, LFOWaveform::sawtooth);
  SamplesEqual(osc.value(), -1.0);
  osc.setPhase(0.25);
  SamplesEqual(osc.value(), -0.5);
  osc.setPhase(0.50);
  SamplesEqual(osc.value(),  0.0);
  osc.setPhase(0.75);
  SamplesEqual(osc.value(),  0.5);
}

- (void)testSetTrianglePhase {
  Parameters::Float freq{1, 1.0};
  LFO<float> osc(freq, 4.0, LFOWaveform::triangle);
  SamplesEqual(osc.value(),  1.0);
  osc.setPhase(0.25);
  SamplesEqual(osc.value(),  0.0);
  osc.setPhase(0.50);
  SamplesEqual(osc.value(), -1.0);
  osc.setPhase(0.75);
  SamplesEqual(osc.value(),  0.0);
}

- (void)testSetSquarePhase {
  Parameters::Float freq{1, 1.0};
  LFO<float> osc(freq, 4.0, LFOWaveform::square);
  SamplesEqual(osc.value(), -1.0);
  osc.setPhase(0.25);
  SamplesEqual(osc.value(), -1.0);
  osc.setPhase(0.50);
  SamplesEqual(osc.value(),  1.0);
  osc.setPhase(0.75);
  SamplesEqual(osc.value(),  1.0);
}

- (void)testSaveRestorePhase {
  Parameters::Float freq{1, 1.0};
  LFO<float> osc(freq, 16.0, LFOWaveform::triangle);
  SamplesEqual(osc.value(),  1.0);
  osc.increment();
  SamplesEqual(osc.value(),  0.75);
  auto saved = osc.phase();
  osc.increment();
  SamplesEqual(osc.value(),  0.50);
  osc.setPhase(saved);
  SamplesEqual(osc.value(),  0.75);
  osc.increment();
  SamplesEqual(osc.value(),  0.50);
  osc.setPhase(saved + 1.0);
  SamplesEqual(osc.value(),  0.75);
  osc.increment();
  SamplesEqual(osc.value(),  0.50);
}

- (void)testPhaseNormalization {
  Parameters::Float freq{1, 10.0};
  LFO<float> osc(freq, 4.0, LFOWaveform::sawtooth);

  osc.setPhase(-0.25);
  SamplesEqual(osc.phase(), 0.75);
  osc.setPhase(2.25);
  SamplesEqual(osc.phase(), 0.25);
  osc.setPhase(std::numeric_limits<float>::infinity());
  SamplesEqual(osc.phase(), 0.0);

  osc.setPhase(0.25);
  osc.increment();
  SamplesEqual(osc.phase(), 0.75);
}

- (void)testPhaseWrappingMatchesFmod {
  Parameters::Float freq{1, 10.0};
  LFO<float> osc(freq, 4.0, LFOWaveform::sawtooth);

  // Reference implementation that always uses `fmod`. A tiny negative value plus 1 rounds to 1, which wraps to 0.
  auto reference = [](float value) {
    value = std::fmod(value, 1.0f);
    if (value < 0.0f) value += 1.0f;
    return value < 1.0f ? value : 0.0f;
  };

  auto check = [&](float value) {
    osc.setPhase(value);
    XCTAssertEqual(osc.phase(), reference(value), @"value: %a", value);
    XCTAssertTrue(osc.phase() >= 0.0f && osc.phase() < 1.0f, @"value: %a phase: %a", value, osc.phase());
  };

  // Sweep across the fast-path ranges (-1, 0) and [1, 2) as well as the `fmod` fallback beyond them.
  for (int step = -3000; step <= 3000; ++step) {
    check(float(step) / 997.0f);
  }

  for (float value : {-2.0f, -1.0f, -0.0f, 0.0f, 1.0f, 2.0f, std::nextafter(1.0f, 0.0f), std::nextafter(2.0f, 0.0f),
    std::nextafter(-1.0f, 0.0f), std::nextafter(-1.0f, -2.0f)}) {
    check(value);
  }
}

- (void)testSinusoidMatchesDoublePrecision {
  Parameters::Float freq{1, 1.0};
  LFO<float> osc(freq, 4.0, LFOWaveform::sinusoid);

  // The single-precision sine must stay within float rounding of the previous double-precision result.
  for (int step = 0; step < 4096; ++step) {
    float phase = float(step) / 4096.0f;
    osc.setPhase(phase);
    double expected = std::sin(std::numbers::pi - double(phase) * 2.0 * std::numbers::pi);
    XCTAssertEqualWithAccuracy(osc.value(), expected, 1.0e-6, @"phase: %f", phase);
  }
}

- (void)testSetWaveformChangesGenerator {
  Parameters::Float freq{1, 1.0};
  LFO<float> osc(freq, 8.0, LFOWaveform::sinusoid);
  osc.setPhase(0.125);
  SamplesEqual(osc.value(), 0.707107);

  osc.setWaveform(LFOWaveform::sawtooth);
  XCTAssertEqual(LFOWaveform::sawtooth, osc.waveform());
  SamplesEqual(osc.value(), -0.75);

  osc.setWaveform(LFOWaveform::triangle);
  SamplesEqual(osc.value(), 0.5);

  osc.setWaveform(LFOWaveform::square);
  SamplesEqual(osc.value(), -1.0);

  osc.setWaveform(LFOWaveform::sinusoid);
  SamplesEqual(osc.value(), 0.707107);
}

- (void)testTinyNegativePhaseWrapsToZero {
  Parameters::Float freq{1, 10.0};
  LFO<float> osc(freq, 4.0, LFOWaveform::sawtooth);

  // Adding 1 to each of these rounds to exactly 1, so the phase must wrap to 0 to stay in [0, 1).
  for (float value : {std::nextafter(0.0f, -1.0f), -std::numeric_limits<float>::min(), -1.0e-10f, -2.9e-8f}) {
    osc.setPhase(value);
    XCTAssertEqual(osc.phase(), 0.0f, @"value: %a", value);
  }

  // Just large enough in magnitude that adding 1 does not round to 1.
  osc.setPhase(-6.0e-8f);
  XCTAssertTrue(osc.phase() > 0.0f && osc.phase() < 1.0f, @"phase: %a", osc.phase());

  // The same holds when an increment steps just below zero.
  freq.setImmediate(-1.0e-10f, 0);
  osc.setPhase(0.0f);
  osc.increment();
  XCTAssertEqual(osc.phase(), 0.0f);
}

- (void)testFrequencyChangeRamping {
  AUValue sampleRate{16.0};
  Parameters::Float freq{1, 1.0};
  LFO<AUValue> osc(freq, sampleRate, LFOWaveform::sinusoid);
  XCTAssertEqual(LFOWaveform::sinusoid, osc.waveform());

  SamplesEqual(osc.value(), 0.0);
  osc.increment();
  SamplesEqual(osc.value(), 0.382683);
  osc.increment();
  SamplesEqual(osc.value(), 0.707107);
  osc.increment();
  SamplesEqual(osc.value(), 0.923889);
  osc.increment();
  SamplesEqual(osc.value(), 1.000000);
  osc.increment();
  SamplesEqual(osc.value(), 0.923880);
  osc.increment();
  SamplesEqual(osc.value(), 0.707107);
  osc.increment();
  SamplesEqual(osc.value(), 0.382683);
  osc.increment();
  SamplesEqual(osc.value(),  0.0);
  freq.setImmediate(2.0, 4);
  osc.increment();
  SamplesEqual(osc.value(), -0.471397);
  osc.increment();
  SamplesEqual(osc.value(), -0.831470);
  osc.increment();
  SamplesEqual(osc.value(), -0.995185);
  osc.increment();
  SamplesEqual(osc.value(), -0.923880);
  osc.increment();
  SamplesEqual(osc.value(), -0.634393);
  osc.increment();
  SamplesEqual(osc.value(), -0.195090);
}


@end
