// Copyright © 2021-2024 Brad Howes. All rights reserved.

#import <type_traits>

#import <XCTest/XCTest.h>
#import "DSPHeaders/Types.hpp"

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
