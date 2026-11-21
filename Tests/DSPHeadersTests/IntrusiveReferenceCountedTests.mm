// Copyright © 2026 Brad Howes. All rights reserved.

#import <XCTest/XCTest.h>
#import <atomic>
#import <thread>
#import <vector>

#import "DSPHeaders/IntrusiveReferenceCounted.hpp"

using namespace DSPHeaders;

namespace {

/// Counts destructor invocations so tests can verify an instance is deleted exactly once.
struct Counted : IntrusiveReferenceCounted<Counted> {
  explicit Counted(std::atomic<int>& deletions) : deletions_{deletions} {}
  ~Counted() { deletions_.fetch_add(1); }

private:
  std::atomic<int>& deletions_;
};

}

@interface IntrusiveReferenceCountedTests : XCTestCase

@end

@implementation IntrusiveReferenceCountedTests

- (void)testRetainRelease {
  std::atomic<int> deletions{0};
  auto counted = new Counted(deletions);
  XCTAssertEqual(1, counted->intrusiveReferenceCount());

  counted->instrusiveReferenceCountedRetain();
  XCTAssertEqual(2, counted->intrusiveReferenceCount());

  counted->instrusiveReferenceCountedRelease();
  XCTAssertEqual(1, counted->intrusiveReferenceCount());
  XCTAssertEqual(0, deletions.load());

  counted->instrusiveReferenceCountedRelease();
  XCTAssertEqual(1, deletions.load());
}

- (void)testConcurrentRetainRelease {
  constexpr int threadCount = 8;
  constexpr int iterations = 100'000;

  for (int trial = 0; trial < 10; ++trial) {
    std::atomic<int> deletions{0};
    auto counted = new Counted(deletions);

    // Each thread holds one reference, churns retain/release pairs, then drops its reference. The last thread to
    // release must be the only one to delete the instance.
    for (int index = 0; index < threadCount; ++index) {
      counted->instrusiveReferenceCountedRetain();
    }
    counted->instrusiveReferenceCountedRelease();

    std::vector<std::thread> threads;
    threads.reserve(threadCount);
    for (int index = 0; index < threadCount; ++index) {
      threads.emplace_back([counted] {
        for (int iteration = 0; iteration < iterations; ++iteration) {
          counted->instrusiveReferenceCountedRetain();
          counted->instrusiveReferenceCountedRelease();
        }
        counted->instrusiveReferenceCountedRelease();
      });
    }

    for (auto& thread : threads) {
      thread.join();
    }

    XCTAssertEqual(1, deletions.load());
  }
}

@end
