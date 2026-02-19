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
  bbs.addMono(0, 12.3);
  bbs.clear(123);

  buffers.push_back(nullptr);
  XCTAssertTrue(bbs.isValid());
  XCTAssertFalse(bbs.isMono());
  XCTAssertTrue(bbs.isStereo());
  XCTAssertEqual(2, bbs.size());
  bbs.addStereo(0, 12.3, 45.6);
  bbs.clear(123);

  buffers.push_back(nullptr);
  XCTAssertTrue(bbs.isValid());
  XCTAssertFalse(bbs.isMono());
  XCTAssertFalse(bbs.isStereo());
  XCTAssertEqual(3, bbs.size());
  bbs.addAlternating(0, 1.234, 5.678);
  bbs.addAll(0, 1.234);
  bbs.clear(123);
}

- (void)testBuffers {
  constexpr int bufSize = 4;
  constexpr int bufferCount = 3;
  std::vector<AUValue*> buffers;
  std::array<std::array<AUValue, bufSize>, bufferCount> bufs;
  buffers.push_back(bufs[0].data());

  auto bbs = BusBuffers(buffers);
  XCTAssertTrue(bbs.isValid());
  XCTAssertTrue(bbs.isMono());

  bbs.clear(bufSize);
  bbs.addMono(0, 1.23);
  XCTAssertEqualWithAccuracy(bufs[0][0], 1.23, 1.e-6);

  buffers.push_back(bufs[1].data());
  bbs.clear(bufSize);
  bbs.addStereo(0, 1.23, 4.56);
  XCTAssertEqualWithAccuracy(bufs[0][0], 1.23, 1.e-6);
  XCTAssertEqualWithAccuracy(bufs[1][0], 4.56, 1.e-6);

  buffers.push_back(bufs[2].data());
  bbs.clear(bufSize);
  bbs.addAll(0, 1.23);
  XCTAssertEqualWithAccuracy(bufs[0][0], 1.23, 1.e-6);
  XCTAssertEqualWithAccuracy(bufs[1][0], 1.23, 1.e-6);
  XCTAssertEqualWithAccuracy(bufs[2][0], 1.23, 1.e-6);

  bbs.addAlternating(1, 4.56, 7.89);
  XCTAssertEqualWithAccuracy(bufs[0][1], 4.56, 1.e-6);
  XCTAssertEqualWithAccuracy(bufs[1][1], 7.89, 1.e-6);
  XCTAssertEqualWithAccuracy(bufs[2][1], 4.56, 1.e-6);
}

@end
