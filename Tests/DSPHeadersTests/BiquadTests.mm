// Copyright © 2021-2024 Brad Howes. All rights reserved.

#import <XCTest/XCTest.h>
#import <cmath>
#import <cstring>
#import <limits>
#import <new>

#import "Pirkle/fxobjects.h"
#import "DSPHeaders/Biquad.hpp"

using namespace DSPHeaders;

#define SamplesEqual(A, B) XCTAssertEqualWithAccuracy(A, B, _epsilon)

@interface BiquadTests : XCTestCase
@property float epsilon;
@end

@implementation BiquadTests

- (void)setUp {
  _epsilon = 0.0001;
}

- (void)testDefaultCoefficients {
  Biquad::Coefficients zeros;
  SamplesEqual(0.0, zeros.a0);
  SamplesEqual(0.0, zeros.a1);
  SamplesEqual(0.0, zeros.a2);
  SamplesEqual(0.0, zeros.b1);
  SamplesEqual(0.0, zeros.b2);
}

- (void)testCoefficients {
  auto coefficients = Biquad::Coefficients()
  .A0(1.0)
  .A1(2.0)
  .A2(3.0)
  .B1(4.0)
  .B2(5.0);
  SamplesEqual(1.0, coefficients.a0);
  SamplesEqual(2.0, coefficients.a1);
  SamplesEqual(3.0, coefficients.a2);
  SamplesEqual(4.0, coefficients.b1);
  SamplesEqual(5.0, coefficients.b2);
}

// The builders work at compile time, return a modified copy, and leave the original unchanged.
static constexpr auto builtCoefficients = Biquad::Coefficients<double>().A0(1.0).A1(2.0).A2(3.0).B1(4.0).B2(5.0);
static_assert(builtCoefficients.a0 == 1.0 && builtCoefficients.a1 == 2.0 && builtCoefficients.a2 == 3.0 &&
              builtCoefficients.b1 == 4.0 && builtCoefficients.b2 == 5.0);
static_assert(builtCoefficients.A0(9.0).a0 == 9.0 && builtCoefficients.a0 == 1.0);
static_assert(std::is_same_v<decltype(std::declval<Biquad::Coefficients<double>&>() += builtCoefficients),
                             Biquad::Coefficients<double>&>);

- (void)testBuildersOnConstCoefficients {
  // The builders are const, so they can be called on a const instance, which must not change.
  const Biquad::Coefficients<double> original(1.0, 2.0, 3.0, 4.0, 5.0);
  auto changed = original.B2(6.0);
  XCTAssertEqual(changed.b2, 6.0);
  XCTAssertEqual(original.b2, 5.0);

  // `operator+=` returns the instance so that additions can be chained.
  Biquad::Coefficients<double> sum;
  (sum += original) += original;
  XCTAssertEqual(sum.a0, 2.0);
  XCTAssertEqual(sum.b2, 10.0);
}

- (void)testNOP {
  Biquad::Coefficients zeros;
  Biquad::Direct<> foo(zeros);
  SamplesEqual(0.0, foo.transform(0.0));
  SamplesEqual(0.0, foo.transform(10.0));
  SamplesEqual(0.0, foo.transform(20.0));
  SamplesEqual(0.0, foo.transform(30.0));
}

- (void)testLPF2Coefficients {
  // Test values taken from https://www.earlevel.com/main/2013/10/13/biquad-calculator-v2/
  double sampleRate = 44100.0;
  Biquad::Coefficients coefficients = Biquad::Coefficients<>::LPF2(sampleRate, 3000.0, 0.707);
  SamplesEqual(0.03478485, coefficients.a0);
  SamplesEqual(0.06956969, coefficients.a1);
  SamplesEqual(0.03478485, coefficients.a2);
  SamplesEqual(-1.40745716, coefficients.b1);
  SamplesEqual(0.54659654, coefficients.b2);
}

- (void)testHPF2Coefficients {
  // Test values taken from https://www.earlevel.com/main/2013/10/13/biquad-calculator-v2/
  double sampleRate = 44100.0;
  Biquad::Coefficients coefficients = Biquad::Coefficients<>::HPF2(sampleRate, 3000.0, 0.707);
  SamplesEqual(0.73851343, coefficients.a0);
  SamplesEqual(-1.47702685, coefficients.a1);
  SamplesEqual(0.73851343, coefficients.a2);
  SamplesEqual(-1.40745716, coefficients.b1);
  SamplesEqual(0.54659654, coefficients.b2);
}

- (void)testReset {
  double sampleRate = 44100.0;
  Biquad::Coefficients coefficients = Biquad::Coefficients<>::LPF1(sampleRate, 8000.0);
  Biquad::Direct<> filter(coefficients);
  SamplesEqual(0.00000, filter.transform(0.0));
  SamplesEqual(0.39056, filter.transform(1.0));
  filter.reset();
  SamplesEqual(0.00000, filter.transform(0.0));
}

// The following tests all compare our Biquad implementation with that found in Pirkle's code to make sure that our
// implementation seems sound.

- (void)testLPF {
  double sampleRate = 44100.0;
  double frequency = 8000.0;

  Biquad::Coefficients coefficients = Biquad::Coefficients<>::LPF1(sampleRate, frequency);
  Biquad::Direct<> filter(coefficients);
  Pirkle::AudioFilterParameters params;
  params.algorithm = Pirkle::filterAlgorithm::kLPF1;
  params.fc = frequency;
  Pirkle::AudioFilter pirkle;
  pirkle.setParameters(params);

  for (int counter = 0; counter < 7200; ++counter) {
    double input = std::sin(counter/10.0 * Pirkle::kPi / 180.0 );
    double output1 = filter.transform(input);
    double output2 = pirkle.processAudioSample(input);
    SamplesEqual(output1, output2);
  }
}

// Compare the output from Will Pirkle's implementation and our own to make sure we have not messed anything up.

- (void)testLPF2 {
  double sampleRate = 44100.0;
  double frequency = 4000.0;

  Biquad::Coefficients coefficients = Biquad::Coefficients<>::LPF2(sampleRate, frequency, 0.707);
  Biquad::Direct<> filter(coefficients);
  Pirkle::AudioFilterParameters params;
  params.algorithm = Pirkle::filterAlgorithm::kLPF2;
  params.fc = frequency;
  Pirkle::AudioFilter pirkle;
  pirkle.setParameters(params);

  // Run over 2 cycles of a sin wave with 0.1 degree step.
  for (int counter = 0; counter < 7200; ++counter) {
    double input = std::sin(counter/10.0 * Pirkle::kPi / 180.0 );
    double output1 = filter.transform(input);
    double output2 = pirkle.processAudioSample(input);
    SamplesEqual(output1, output2);
  }
}

// Compare the output from Will Pirkle's implementation and our own to make sure we have not messed anything up.

- (void)testHPF2 {
  double sampleRate = 44100.0;
  double frequency = 8000.0;

  Biquad::Coefficients coefficients = Biquad::Coefficients<>::HPF2(sampleRate, frequency, 0.707);
  Biquad::Direct<> filter(coefficients);
  Pirkle::AudioFilterParameters params;
  params.algorithm = Pirkle::filterAlgorithm::kHPF2 ;
  params.fc = frequency;
  Pirkle::AudioFilter pirkle;
  pirkle.setParameters(params);

  for (int counter = 0; counter < 7200; ++counter) {
    double input = std::sin(counter/10.0 * Pirkle::kPi / 180.0 );
    double output1 = filter.transform(input);
    double output2 = pirkle.processAudioSample(input);
    SamplesEqual(output1, output2);
  }
}

- (void)testHPF {
  double sampleRate = 44100.0;
  double frequency = 8000.0;

  Biquad::Coefficients coefficients = Biquad::Coefficients<>::HPF1(sampleRate, frequency);
  Biquad::Direct<> filter(coefficients);
  Pirkle::AudioFilterParameters params;
  params.algorithm = Pirkle::filterAlgorithm::kHPF1;
  params.fc = frequency;
  Pirkle::AudioFilter pirkle;
  pirkle.setParameters(params);

  for (int counter = 0; counter < 7200; ++counter) {
    double input = std::sin(counter/10.0 * Pirkle::kPi / 180.0 );
    double output1 = filter.transform(input);
    double output2 = pirkle.processAudioSample(input);
    SamplesEqual(output1, output2);
  }
}

- (void)testAPF1 {
  double sampleRate = 44100.0;
  double frequency = 4000.0;

  Biquad::Coefficients coefficients = Biquad::Coefficients<>::APF1(sampleRate, frequency);
  Biquad::Direct<> filter(coefficients);
  Pirkle::AudioFilterParameters params;
  params.algorithm = Pirkle::filterAlgorithm::kAPF1;
  params.fc = frequency;
  Pirkle::AudioFilter pirkle;
  pirkle.setParameters(params);

  for (int counter = 0; counter < 7200; ++counter) {
    double input = std::sin(counter/10.0 * M_PI / 180.0 );
    double output1 = filter.transform(input);
    double output2 = pirkle.processAudioSample(input);
    SamplesEqual(output1, output2);
  }
}

- (void)testAPF2 {
  double sampleRate = 44100.0;
  double frequency = 4000.0;

  Biquad::Coefficients coefficients = Biquad::Coefficients<>::APF2(sampleRate, frequency, 0.707);
  Biquad::Direct<> filter(coefficients);
  Pirkle::AudioFilterParameters params;
  params.algorithm = Pirkle::filterAlgorithm::kAPF2;
  params.fc = frequency;
  Pirkle::AudioFilter pirkle;
  pirkle.setParameters(params);

  for (int counter = 0; counter < 7200; ++counter) {
    double input = std::sin(counter/10.0 * M_PI / 180.0 );
    double output1 = filter.transform(input);
    double output2 = pirkle.processAudioSample(input);
    SamplesEqual(output1, output2);
  }
}

- (void)testRamping {
  double sampleRate = 44100.0;
  double frequency = 4000.0;
  size_t rampCount = 8;

  Biquad::Coefficients coefficients{Biquad::Coefficients<>::LPF2(sampleRate, frequency, 0.707)};
  Biquad::Direct<> filter{coefficients};

  Pirkle::AudioFilterParameters params;
  params.algorithm = Pirkle::filterAlgorithm::kLPF2;
  params.fc = frequency;
  Pirkle::AudioFilter pirkle;
  pirkle.setParameters(params);

  // Run over 2 cycles of a sin wave with 0.1 degree step.
  int counter;
  auto inputGenerator = [](int counter) -> double { return std::sin(counter/10.0 * Pirkle::kPi / 180.0 ); };

  for (counter = 0; counter < 7200; ++counter) {
    double input = inputGenerator(counter);
    double output1 = filter.transform(input);
    double output2 = pirkle.processAudioSample(input);
    // double output3 = ramping.transform(input);
    SamplesEqual(output1, output2);
  }

  // Ramp to a new value
  coefficients = Biquad::Coefficients<>::LPF2(sampleRate, 2000.0, 0.707);
  filter.setCoefficients(coefficients);
  Biquad::Direct<> ramping{coefficients};
  ramping.setCoefficients(coefficients, rampCount);

  // We expect that for rampCount samples the ramped and un-ramped filters would not match. However, even after the
  // ramping is complete, the ramped filter still has memory that must get cycled out before it begins to emit values
  // like the un-ramped version.
  for (counter = 0; counter < (rampCount + 1) * 2; ++counter) {
    double input = inputGenerator(counter);
    XCTAssertNotEqualWithAccuracy(filter.transform(input), ramping.transform(input), _epsilon);
  }

  // From this point on, they filters should match.
  for (; counter < 7200; ++counter) {
    double input = inputGenerator(counter);
    XCTAssertEqualWithAccuracy(filter.transform(input), ramping.transform(input), _epsilon);
  }
}

- (void)testForceMinToZero {
  using Base = Biquad::Transform::Base<float>;
  constexpr float noiseFloor = 2.0e-10f;

  // The previous four-comparison implementation, kept as the reference.
  auto reference = [&](float value) {
    return (value > 0.0f && value <= noiseFloor) || (value < 0.0f && -value <= noiseFloor) ? 0.0f : value;
  };

  for (float value : {0.0f, 1.0e-12f, -1.0e-12f, noiseFloor, -noiseFloor, std::nextafter(noiseFloor, 1.0f),
    -std::nextafter(noiseFloor, 1.0f), 1.0e-5f, -1.0e-5f, 0.5f, -0.5f, 1.0f, -1.0f,
    std::numeric_limits<float>::denorm_min(), std::numeric_limits<float>::infinity()}) {
    XCTAssertEqual(Base::forceMinToZero(value), reference(value), @"value: %a", value);
  }

  XCTAssertTrue(std::isnan(Base::forceMinToZero(std::numeric_limits<float>::quiet_NaN())));
}

- (void)testReadingCoefficientsDoesNotAdvanceRamp {
  double sampleRate = 44100.0;
  auto start = Biquad::Coefficients<>::LPF2(sampleRate, 4000.0, 0.707);
  auto goal = Biquad::Coefficients<>::LPF2(sampleRate, 2000.0, 0.707);
  size_t rampCount = 8;

  // Two filters ramp identically, but one has its coefficients read between samples. Reads must not change the ramp.
  Biquad::CanonicalTranspose<> plain{start};
  Biquad::CanonicalTranspose<> inspected{start};
  plain.setCoefficients(goal, rampCount);
  inspected.setCoefficients(goal, rampCount);

  for (int sample = 0; sample < 32; ++sample) {
    double input = std::sin(sample / 5.0);
    for (int read = 0; read < 3; ++read) {
      (void)inspected.gainValue();
      (void)inspected.storageComponent();
    }
    XCTAssertEqual(plain.transform(input), inspected.transform(input), @"sample: %d", sample);
    XCTAssertEqual(plain.gainValue(), inspected.gainValue(), @"sample: %d", sample);
  }

  // After the ramp completes the gain is the goal's gain.
  XCTAssertEqual(plain.gainValue(), goal.a0);
}

- (void)testImmediateCoefficientsCancelRamp {
  double sampleRate = 44100.0;
  auto start = Biquad::Coefficients<>::LPF2(sampleRate, 4000.0, 0.707);
  auto rampGoal = Biquad::Coefficients<>::LPF2(sampleRate, 2000.0, 0.707);
  auto immediate = Biquad::Coefficients<>::LPF2(sampleRate, 1000.0, 0.707);

  Biquad::Direct<> filter{start};
  filter.setCoefficients(rampGoal, 8);
  filter.transform(0.5);
  filter.transform(0.5);

  // An immediate change replaces an active ramp; later samples must not continue toward the old goal.
  filter.setCoefficients(immediate);
  XCTAssertEqual(filter.gainValue(), immediate.a0);
  for (int sample = 0; sample < 16; ++sample) filter.transform(0.5);
  XCTAssertEqual(filter.gainValue(), immediate.a0);

  // Temporaries bind to the const reference overload, with or without a ramp.
  filter.setCoefficients(Biquad::Coefficients<>::LPF2(sampleRate, 3000.0, 0.707), 4);
  for (int sample = 0; sample < 4; ++sample) filter.transform(0.5);
  XCTAssertEqualWithAccuracy(filter.gainValue(), Biquad::Coefficients<>::LPF2(sampleRate, 3000.0, 0.707).a0, 1.0e-12);
}

/**
 Default-initialize a `T` (as for a class member not named in a constructor's initializer list) in storage filled with
 0xFF bytes, which are NaN for floating-point values. Members without initializers keep those bytes, so any of them
 that the type leaves indeterminate shows up as NaN.
 */
template <typename T, typename Check>
static void withDefaultInitialized(Check check) {
  alignas(T) unsigned char storage[sizeof(T)];
  std::memset(storage, 0xFF, sizeof(storage));
  T* value = new (storage) T;
  check(*value);
  value->~T();
}

- (void)testDefaultInitializedValuesAreZero {
  withDefaultInitialized<Biquad::State<float>>([](const auto& state) {
    XCTAssertEqual(state.x_z1, 0.0f);
    XCTAssertEqual(state.x_z2, 0.0f);
    XCTAssertEqual(state.y_z1, 0.0f);
    XCTAssertEqual(state.y_z2, 0.0f);
  });

  withDefaultInitialized<Biquad::Coefficients<double>>([](const auto& coefficients) {
    XCTAssertEqual(coefficients.a0, 0.0);
    XCTAssertEqual(coefficients.a1, 0.0);
    XCTAssertEqual(coefficients.a2, 0.0);
    XCTAssertEqual(coefficients.b1, 0.0);
    XCTAssertEqual(coefficients.b2, 0.0);
  });
}

- (void)testDefaultInitializedFilterStartsFromZeroState {
  // A filter with zero coefficients and zero state produces zero output; indeterminate state would produce NaN.
  withDefaultInitialized<Biquad::Direct<float>>([](auto& filter) {
    XCTAssertEqual(filter.storageComponent(), 0.0f);
    XCTAssertEqual(filter.transform(1.0f), 0.0f);
  });

  // Once given coefficients, the first output must depend only on the input.
  withDefaultInitialized<Biquad::CanonicalTranspose<double>>([](auto& filter) {
    filter.setCoefficients(Biquad::Coefficients<double>::LPF2(44100.0, 3000.0, 0.707));
    auto expected = Biquad::Coefficients<double>::LPF2(44100.0, 3000.0, 0.707).a0 * 0.5;
    XCTAssertEqualWithAccuracy(filter.transform(0.5), expected, 1.0e-12);
  });
}

@end
