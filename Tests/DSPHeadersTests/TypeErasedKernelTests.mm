// Copyright © 2026 Brad Howes. All rights reserved.

#import <XCTest/XCTest.h>
#import <memory>
#import <utility>

#import "DSPHeaders/TypeErasedKernel.hpp"

using namespace DSPHeaders;

/// Callable that counts how many times it is copied and records the arguments of the last call.
struct CountingRender {
  std::shared_ptr<int> copies;
  std::shared_ptr<UInt32> lastFrameCount;

  CountingRender() : copies{std::make_shared<int>(0)}, lastFrameCount{std::make_shared<UInt32>(0)} {}
  CountingRender(const CountingRender& other) : copies{other.copies}, lastFrameCount{other.lastFrameCount} {
    ++*copies;
  }
  CountingRender(CountingRender&&) = default;

  AUAudioUnitStatus operator()(const AudioTimeStamp*, UInt32 frameCount, NSInteger, AudioBufferList*,
                               const AURenderEvent*, AURenderPullInputBlock) const {
    *lastFrameCount = frameCount;
    return 123;
  }
};

@interface TypeErasedKernelTests : XCTestCase
@end

@implementation TypeErasedKernelTests

- (void)testConstructorsMoveInsteadOfCopying {
  CountingRender render;
  auto copies = render.copies;

  // Moving the callable through both constructors must not copy it.
  TypeErasedKernel kernel{TypeErasedKernel::ProcessAndRender{std::move(render)}};
  RenderBlockShim shim{std::move(kernel)};
  XCTAssertEqual(*copies, 0);
}

- (void)testRenderBlockCallsKernelAndOutlivesShim {
  CountingRender render;
  auto lastFrameCount = render.lastFrameCount;

  AUInternalRenderBlock block;
  {
    RenderBlockShim shim{TypeErasedKernel{TypeErasedKernel::ProcessAndRender{std::move(render)}}};
    block = shim.internalRenderBlock();
  }

  // The block holds its own copy of the callable, so it still works after the shim is gone.
  AudioTimeStamp timestamp = AudioTimeStamp();
  AudioUnitRenderActionFlags flags = 0;
  AudioBufferList output{};
  XCTAssertEqual(block(&flags, &timestamp, 256, 0, &output, nullptr, nil), 123);
  XCTAssertEqual(*lastFrameCount, 256u);
}

- (void)testRenderBlockWithoutKernelReportsUninitialized {
  RenderBlockShim shim{TypeErasedKernel{}};
  AUInternalRenderBlock block = shim.internalRenderBlock();
  AudioTimeStamp timestamp = AudioTimeStamp();
  AudioUnitRenderActionFlags flags = 0;
  AudioBufferList output{};
  XCTAssertEqual(block(&flags, &timestamp, 256, 0, &output, nullptr, nil), kAudioUnitErr_Uninitialized);
}

@end
