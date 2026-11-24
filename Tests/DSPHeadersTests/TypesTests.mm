// Copyright © 2021-2024 Brad Howes. All rights reserved.

#import <stdexcept>
#import <type_traits>
#import <vector>

#import <XCTest/XCTest.h>
#import "DSPHeaders/Accelerated.hpp"
#import "DSPHeaders/Types.hpp"

// The routine pointers are compile-time constants naming the vDSP routine for each type.
static_assert(DSPHeaders::Accelerated<float>::zeroProc == vDSP_vclr);
static_assert(DSPHeaders::Accelerated<double>::zeroProc == vDSP_vclrD);
static_assert(DSPHeaders::Accelerated<float>::conversionProc == vDSP_vflt16);
static_assert(DSPHeaders::Accelerated<double>::conversionProc == vDSP_vflt16D);
static_assert(DSPHeaders::Accelerated<float>::scaleProc == vDSP_vsmul);
static_assert(DSPHeaders::Accelerated<double>::scaleProc == vDSP_vsmulD);
static_assert(DSPHeaders::Accelerated<float>::magnitudeProc == vDSP_maxmgv);
static_assert(DSPHeaders::Accelerated<double>::magnitudeProc == vDSP_maxmgvD);

using namespace DSPHeaders;

@interface TypesTests : XCTestCase

@end

@implementation TypesTests

- (void)testValueOf {
  enum Foo { one = 1, two = 2 };
  XCTAssertEqual(DSPHeaders::valueOf(Foo::one), 1);
}

- (void)testConstantOperators {
  auto tmp1 = 0_F;
  static_assert(std::is_same_v<decltype(tmp1), long double> == true);
  auto tmp2 = 123123123123_F;
  static_assert(std::is_same_v<decltype(tmp2), long double> == true);
  auto tmp3 = 0.1234_F;
  static_assert(std::is_same_v<decltype(tmp3), long double> == true);

  float tmp4 = 0.1234_F;
  double tmp5 = 0.1234_F;
}

- (void)testCheckedVectorIndexing {
  std::vector<int> values{10, 20, 30};
  const auto& constValues = values;

  // `noexcept` only when indices are not checked, so a checked out-of-range index throws instead of terminating.
  static_assert(noexcept(DSPHeaders::checkedVectorIndexing(values, 0)) ==
                !DSPHeaders::checkedVectorIndexingEnabled);
  static_assert(noexcept(DSPHeaders::checkedVectorIndexing(constValues, size_t(0))) ==
                !DSPHeaders::checkedVectorIndexingEnabled);

  // Any index type convertible to `size_t` works, for both const and mutable containers.
  XCTAssertEqual(DSPHeaders::checkedVectorIndexing(constValues, size_t(1)), 20);
  XCTAssertEqual(DSPHeaders::checkedVectorIndexing(constValues, 2), 30);
  DSPHeaders::checkedVectorIndexing(values, 0u) = 11;
  XCTAssertEqual(values[0], 11);

  if constexpr (DSPHeaders::checkedVectorIndexingEnabled) {
    bool threw = false;
    try {
      (void)DSPHeaders::checkedVectorIndexing(values, 3);
    } catch (const std::out_of_range&) {
      threw = true;
    }
    XCTAssertTrue(threw);
  }
}

@end
