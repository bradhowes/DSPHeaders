// Copyright © 2021-2024 Brad Howes. All rights reserved.

#import <XCTest/XCTest.h>
#import <vector>

#import "DSPHeaders/EventProcessor.hpp"

using namespace DSPHeaders;

@interface BusBuffersTests : XCTestCase

@end

@implementation BusBuffersTests

- (void)setUp {
  // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
  // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testEmpty {
  std::vector<AUValue*> buffers;
  auto bbs = BusBuffers(buffers);
  XCTAssertFalse(bbs.isValid());
  XCTAssertFalse(bbs.isMono());
  XCTAssertFalse(bbs.isStereo());
}

- (void)testNulls {
  std::vector<AUValue*> buffers;
  buffers.push_back(nullptr);
  auto bbs = BusBuffers(buffers);
  XCTAssertTrue(bbs.isValid());
  XCTAssertTrue(bbs.isMono());
  XCTAssertFalse(bbs.isStereo());
  XCTAssertEqual(1, bbs.size());
  bbs.clear(123);

  buffers.push_back(nullptr);
  XCTAssertTrue(bbs.isValid());
  XCTAssertFalse(bbs.isMono());
  XCTAssertTrue(bbs.isStereo());
  XCTAssertEqual(2, bbs.size());
  bbs.clear(123);

  buffers.push_back(nullptr);
  XCTAssertTrue(bbs.isValid());
  XCTAssertFalse(bbs.isMono());
  XCTAssertFalse(bbs.isStereo());
  XCTAssertEqual(3, bbs.size());
  bbs.clear(123);
}

@end
