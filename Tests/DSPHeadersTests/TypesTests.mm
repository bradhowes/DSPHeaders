// Copyright © 2021-2024 Brad Howes. All rights reserved.

#import <type_traits>

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
  static_assert(std::is_same_v<decltype(tmp1), double> == true);
  auto tmp2 = 123123123123_F;
  static_assert(std::is_same_v<decltype(tmp2), double> == true);
  auto tmp3 = 0.1234_F;
  static_assert(std::is_same_v<decltype(tmp3), double> == true);
}

@end
