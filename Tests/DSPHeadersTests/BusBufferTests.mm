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

- (void)testAddAlternatingChannelCounts {
  // Cover even and odd channel counts, so both the paired loop and the trailing even channel are exercised, along
  // with channels that have no buffer.
  constexpr size_t maxChannels = 5;
  std::array<AUValue, maxChannels> samples{};
  for (size_t count = 1; count <= maxChannels; ++count) {
    std::vector<AUValue*> buffers;
    for (size_t index = 0; index < count; ++index) {
      buffers.push_back(index == 1 ? nullptr : &samples[index]);
    }
    samples.fill(0.0);
    BusBuffers(buffers).addAlternating(0, 1.0, 2.0);
    for (size_t index = 0; index < count; ++index) {
      AUValue expected = index == 1 ? 0.0 : (index % 2 == 0 ? 1.0 : 2.0);
      XCTAssertEqual(samples[index], expected, @"count: %zu index: %zu", count, index);
    }
  }
}

- (void)testChannelSpans {
  constexpr AUAudioFrameCount frameCount = 4;
  std::array<std::array<AUValue, frameCount>, 2> bufs{};
  std::vector<AUValue*> buffers{bufs[0].data(), nullptr, bufs[1].data()};
  BusBuffers bbs(buffers);

  auto left = bbs.channel(0, frameCount);
  XCTAssertEqual(left.data(), bufs[0].data());
  XCTAssertEqual(left.size(), frameCount);
  for (size_t frame = 0; frame < left.size(); ++frame) left[frame] = AUValue(frame + 1);
  XCTAssertEqual(bufs[0][3], 4.0);

  // A channel without a buffer gives an empty span, so a loop over it does nothing.
  XCTAssertTrue(bbs.channel(1, frameCount).empty());

  auto channels = bbs.channels();
  XCTAssertEqual(channels.size(), 3);
  XCTAssertEqual(channels[2], bufs[1].data());
  XCTAssertEqual(channels[1], nullptr);
}

@end
