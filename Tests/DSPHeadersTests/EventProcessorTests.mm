// Copyright © 2021-2024 Brad Howes. All rights reserved.

#import <XCTest/XCTest.h>
#import <algorithm>
#import <cmath>

#import "DSPHeaders/DSP.hpp"
#import "DSPHeaders/EventProcessor.hpp"
#import "DSPHeaders/Parameters/Float.hpp"

using namespace DSPHeaders;

struct MockEffect : public EventProcessor<MockEffect>
{
  using super = EventProcessor<MockEffect>;

  MockEffect() : super("mock") {
    registerParameter(param_);
  }

  bool doSetImmediateParameterValue(AUParameterAddress address, AUValue value, AUAudioFrameCount duration) {
    if (address == 1) param_.setImmediate(value, duration);
    return address == 1;
  }

  bool doSetPendingParameterValue(AUParameterAddress address, AUValue value) {
    if (address == 1) param_.setPending(value);
    return address == 1;
  }

  AUValue doGetImmediateParameterValue(AUParameterAddress address) const {
    return address == 1 ? param_.getImmediate() : 0.0;
  }

  AUValue doGetPendingParameterValue(AUParameterAddress address) const {
    return address == 1 ? param_.getPending() : 0.0;
  }

  void doRendering(BusBuffers, BusBuffers, AUAudioFrameCount frameCount) {
    paramValues_.push_back(param_.frameValue());
    frameCounts_.push_back(frameCount);
  }

  bool checkForTreeBasedParameterChanges() { return super::checkForParameterValueChanges(); }

  Parameters::Float param_{1, 0.0};
  std::vector<AUAudioFrameCount> paramValues_{};
  std::vector<AUAudioFrameCount> frameCounts_{};
};

// To validate the API of the MockEffect
ValidatedKernel<MockEffect> _mockEffect_minMockEffect;

/// Kernel with several parameters that relies on the default parameter handling in `EventProcessor`.
struct MultiParameterEffect : public EventProcessor<MultiParameterEffect>
{
  using super = EventProcessor<MultiParameterEffect>;

  MultiParameterEffect() : super("multi") {
    registerParameters({first_, second_, third_});
  }

  void doRendering(BusBuffers, BusBuffers, AUAudioFrameCount) {}

  bool checkForTreeBasedParameterChanges() { return super::checkForParameterValueChanges(); }

  Parameters::Float first_{1, 0.0, false};
  Parameters::Float second_{2, 0.0, false};
  Parameters::Float third_{3, 0.0};
};

@interface EventProcessorTests : XCTestCase
@property MockEffect* effect;
@end

@implementation EventProcessorTests {
  AUValue epsilon;
}

- (void)setUp {
  epsilon = 1.0E-6;
  self.effect = new MockEffect();
  [self setRenderingFormat];
}

- (void)setRenderingFormat {
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AUAudioFrameCount maxFrames = 512;
  self.effect->setRenderingFormat(1, format, maxFrames);
}

- (void)tearDown {
  delete self.effect;
}

- (void)testInit {
  XCTAssertTrue(self.effect->isRendering());
}

- (void)testAllRegisteredParametersAreChecked {
  MultiParameterEffect effect;
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  effect.setRenderingFormat(1, format, 512);

  // Pending changes from the parameter tree on every registered parameter are seen in one render-block check.
  XCTAssertTrue(effect.setParameterValue(1, 0.25));
  XCTAssertTrue(effect.setParameterValue(2, 0.5));
  XCTAssertTrue(effect.setParameterValue(3, 1.0));
  XCTAssertTrue(effect.checkForTreeBasedParameterChanges());
  XCTAssertEqual(effect.first_.frameValue(), 0.25);
  XCTAssertEqual(effect.second_.frameValue(), 0.5);
  XCTAssertTrue(effect.third_.isRamping());

  // Stopping rendering stops the ramp on every registered parameter, leaving each at its pending value.
  effect.deallocateRenderResources();
  XCTAssertFalse(effect.third_.isRamping());
  XCTAssertEqual(effect.third_.frameValue(), 1.0);

  // Lookups by address still work, including for an unknown address.
  XCTAssertEqual(effect.getParameterValue(2), 0.5);
  XCTAssertFalse(effect.setParameterValue(99, 1.0));
}

- (void)testRenderLoggingDisabledByDefault {
  XCTAssertFalse(MockEffect::renderLoggingEnabled);
}

- (void)testBypass {
  XCTAssertFalse(self.effect->isBypassed());
  self.effect->setBypass(true);
  XCTAssertTrue(self.effect->isBypassed());
  self.effect->setBypass(false);
  XCTAssertFalse(self.effect->isBypassed());
}

- (void)testRenderingState {
  XCTAssertTrue(self.effect->isRendering());
  self.effect->deallocateRenderResources();
  XCTAssertFalse(self.effect->isRendering());
}

AURenderPullInputBlock mockPullInput = ^(AudioUnitRenderActionFlags* actionFlags, const AudioTimeStamp *timestamp,
                                         AUAudioFrameCount frameCount, NSInteger inputBusNumber,
                                         AudioBufferList* inputData) {
  auto bufferCount = inputData->mNumberBuffers;
  XCTAssertEqual(bufferCount, 2);
  for (int bufferIndex = 0; bufferIndex < bufferCount; ++bufferIndex) {
    auto& buffer = inputData->mBuffers[bufferIndex];
    auto numberOfChannels = buffer.mNumberChannels;
    XCTAssertEqual(numberOfChannels, 1);
    auto bufferSize = buffer.mDataByteSize;
    XCTAssertEqual(sizeof(AUValue) * frameCount, bufferSize);
    auto ptr = static_cast<AUValue*>(buffer.mData);
    for (int frameIndex = 0; frameIndex < frameCount; ++frameIndex) {
      ptr[frameIndex] = frameIndex;
    }
  }

  return 0;
};

- (void)testProcessAndRenderNoPullInput {
  self.effect->setBypass(true);
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AUAudioFrameCount maxFrames = 512;

  AudioTimeStamp timestamp = AudioTimeStamp();

  // Test without a pullInput routine
  AUAudioFrameCount frames = maxFrames;
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:maxFrames];
  AudioBufferList* outputData = [buffer mutableAudioBufferList];
  auto status = self.effect->processAndRender(&timestamp, frames, 0, outputData, nullptr, nullptr);
  XCTAssertEqual(status, 0);
  XCTAssertTrue(self.effect->frameCounts_.empty());

  AudioBuffer& left = outputData->mBuffers[0];
  XCTAssertEqual(left.mNumberChannels, 1);
  XCTAssertEqual(left.mDataByteSize, maxFrames * sizeof(AUValue));

  AudioBuffer& right = outputData->mBuffers[1];
  XCTAssertEqual(right.mNumberChannels, 1);
  XCTAssertEqual(right.mDataByteSize, maxFrames * sizeof(AUValue));
}

- (void)testProcessAndRenderWithPullInput {
  self.effect->setBypass(true);
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AUAudioFrameCount maxFrames = 512;

  AudioTimeStamp timestamp = AudioTimeStamp();

  // Test without a pullInput routine
  AUAudioFrameCount frames = maxFrames;
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:maxFrames];
  AudioBufferList *outputData = [buffer mutableAudioBufferList];
  auto status = self.effect->processAndRender(&timestamp, frames, 0, outputData, nullptr, mockPullInput);
  XCTAssertEqual(status, 0);
  XCTAssertTrue(self.effect->frameCounts_.empty());

  AudioBuffer& left = outputData->mBuffers[0];
  XCTAssertEqual(left.mNumberChannels, 1);
  XCTAssertEqual(left.mDataByteSize, maxFrames * sizeof(AUValue));
  auto ptr = static_cast<AUValue*>(left.mData);
  XCTAssertEqual(ptr[maxFrames - 1], 511.0);

  AudioBuffer& right = outputData->mBuffers[1];
  XCTAssertEqual(right.mNumberChannels, 1);
  XCTAssertEqual(right.mDataByteSize, maxFrames * sizeof(AUValue));
  ptr = static_cast<AUValue*>(right.mData);
  XCTAssertEqual(ptr[maxFrames - 1], 511.0);
}

- (void)testProcessAndRenderingInPlace {
  self.effect->setBypass(true);
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AUAudioFrameCount maxFrames = 512;

  AudioTimeStamp timestamp = AudioTimeStamp();

  // Test without a pullInput routine
  AUAudioFrameCount frames = maxFrames;
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:maxFrames];
  AudioBufferList *outputData = [buffer mutableAudioBufferList];

  outputData->mBuffers[0].mData = nil;
  outputData->mBuffers[1].mData = nil;

  auto status = self.effect->processAndRender(&timestamp, frames, 0, outputData, nullptr, mockPullInput);
  XCTAssertEqual(status, 0);
  XCTAssertTrue(self.effect->frameCounts_.empty());

  AudioBuffer& left = outputData->mBuffers[0];
  XCTAssertEqual(left.mNumberChannels, 1);
  XCTAssertEqual(left.mDataByteSize, maxFrames * sizeof(AUValue));
  auto ptr = static_cast<AUValue*>(left.mData);
  XCTAssertEqual(ptr[maxFrames - 1], 511.0);

  AudioBuffer& right = outputData->mBuffers[1];
  XCTAssertEqual(right.mNumberChannels, 1);
  XCTAssertEqual(right.mDataByteSize, maxFrames * sizeof(AUValue));
  ptr = static_cast<AUValue*>(right.mData);
  XCTAssertEqual(ptr[maxFrames - 1], 511.0);
}

- (void)testEventRampingDuration {
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AUAudioFrameCount maxFrames = 512;
  AudioTimeStamp timestamp = AudioTimeStamp();
  AUAudioFrameCount frames = maxFrames;
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:maxFrames];
  AudioBufferList *outputData = [buffer mutableAudioBufferList];
  outputData->mBuffers[0].mData = nil;
  outputData->mBuffers[1].mData = nil;

  // Set a parameter that ramps for 4 samples
  AUParameterEvent* rampingEvent = new AUParameterEvent();
  rampingEvent->next = nullptr;
  rampingEvent->eventSampleTime = -1;
  rampingEvent->parameterAddress = 1;
  rampingEvent->rampDurationSampleFrames = 4;
  rampingEvent->value = 10;

  AURenderEvent* eventList = reinterpret_cast<AURenderEvent*>(rampingEvent);
  eventList->head.eventType = AURenderEventParameterRamp;

  // Do rendering for 512 samples. Expectation is 4 1-sample render calls and then 1 508 sample render.
  auto status = self.effect->processAndRender(&timestamp, frames, 0, outputData, eventList, mockPullInput);
  XCTAssertEqual(status, 0);
  XCTAssertEqual(self.effect->param_.getImmediate(), 10.0);
  XCTAssertEqual(self.effect->param_.getPending(), 10.0);
  XCTAssertEqual(self.effect->frameCounts_.size(), 1);
  XCTAssertEqual(self.effect->frameCounts_[0], 512);
//  XCTAssertEqual(self.effect->frameCounts_[1], 1);
//  XCTAssertEqual(self.effect->frameCounts_[2], 1);
//  XCTAssertEqual(self.effect->frameCounts_[3], 1);
//  XCTAssertEqual(self.effect->frameCounts_[4], 508);
}

- (void)testHostRampDurationIsInFrames {
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AUAudioFrameCount frames = 512;
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frames];
  AudioBufferList* outputData = [buffer mutableAudioBufferList];
  outputData->mBuffers[0].mData = nil;
  outputData->mBuffers[1].mData = nil;
  AudioTimeStamp timestamp = AudioTimeStamp();

  // A host ramp of 1024 frames with 512-frame render calls must take 2 render calls, not 1024.
  AUParameterEvent event{};
  event.next = nullptr;
  event.eventSampleTime = -1;
  event.parameterAddress = 1;
  event.rampDurationSampleFrames = 1024;
  event.value = 10;
  AURenderEvent* eventList = reinterpret_cast<AURenderEvent*>(&event);
  eventList->head.eventType = AURenderEventParameterRamp;

  XCTAssertEqual(self.effect->processAndRender(&timestamp, frames, 0, outputData, eventList, mockPullInput), 0);
  XCTAssertEqual(self.effect->paramValues_.back(), 5);
  XCTAssertEqual(self.effect->rampRemaining(), 1);

  timestamp.mSampleTime += frames;
  XCTAssertEqual(self.effect->processAndRender(&timestamp, frames, 0, outputData, nullptr, mockPullInput), 0);
  XCTAssertEqual(self.effect->paramValues_.back(), 10);
  XCTAssertFalse(self.effect->param_.isRamping());

  // A partial final block still counts as a render call: 1025 frames needs 3 calls of 512 frames.
  XCTAssertEqual(MockEffect::rampFramesToRenderCalls(1025, 512), 3);
  XCTAssertEqual(MockEffect::rampFramesToRenderCalls(512, 512), 1);
  XCTAssertEqual(MockEffect::rampFramesToRenderCalls(4, 512), 1);
  XCTAssertEqual(MockEffect::rampFramesToRenderCalls(0, 512), 0);
}

- (void)testZeroLengthHostRampIsImmediate {
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AUAudioFrameCount frames = 512;
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frames];
  AudioBufferList* outputData = [buffer mutableAudioBufferList];
  outputData->mBuffers[0].mData = nil;
  outputData->mBuffers[1].mData = nil;
  AudioTimeStamp timestamp = AudioTimeStamp();

  AUParameterEvent event{};
  event.next = nullptr;
  event.eventSampleTime = -1;
  event.parameterAddress = 1;
  event.rampDurationSampleFrames = 0;
  event.value = 10;
  AURenderEvent* eventList = reinterpret_cast<AURenderEvent*>(&event);
  eventList->head.eventType = AURenderEventParameterRamp;

  // A ramp duration of 0 means an immediate change. It must not underflow into a ~4 billion call ramp.
  XCTAssertEqual(self.effect->processAndRender(&timestamp, frames, 0, outputData, eventList, mockPullInput), 0);
  XCTAssertEqual(self.effect->paramValues_.back(), 10);
  XCTAssertEqual(self.effect->rampRemaining(), 0);
  XCTAssertFalse(self.effect->isRamping());
}

- (void)testFutureEventDoesNotExceedRenderBlock {
  AudioTimeStamp timestamp = AudioTimeStamp();
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:512];
  AudioBufferList* outputData = [buffer mutableAudioBufferList];

  AUParameterEvent event{};
  event.next = nullptr;
  event.eventSampleTime = 4;
  event.parameterAddress = 1;
  event.rampDurationSampleFrames = 4;
  event.value = 10;

  AURenderEvent* eventList = reinterpret_cast<AURenderEvent*>(&event);
  eventList->head.eventType = AURenderEventParameterRamp;

  auto status = self.effect->processAndRender(&timestamp, 2, 0, outputData, eventList, mockPullInput);

  XCTAssertEqual(status, 0);
  XCTAssertEqual(self.effect->frameCounts_.size(), 1);
  XCTAssertEqual(self.effect->frameCounts_[0], 2);
  XCTAssertEqual(self.effect->param_.frameValue(), 0.0);
}

- (void)testUIRampingDuration {
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AUAudioFrameCount maxFrames = 512;
  AudioTimeStamp timestamp = AudioTimeStamp();
  AUAudioFrameCount frames = maxFrames;
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:maxFrames];
  AudioBufferList *outputData = [buffer mutableAudioBufferList];
  outputData->mBuffers[0].mData = nil;
  outputData->mBuffers[1].mData = nil;

  AUAudioFrameCount rampDuration = 32;
  self.effect->deallocateRenderResources();
  self.effect->setRenderingFormat(1, format, maxFrames, rampDuration);

  // Set a parameter that ramps for 32 render cycle
  self.effect->param_.setPending(882.0);
  XCTAssertEqual(self.effect->param_.getPending(), 882.0);
  XCTAssertEqual(self.effect->param_.getImmediate(), 882.0);
  XCTAssertEqual(self.effect->param_.frameValue(), 0.0);
  XCTAssertTrue(self.effect->param_.canRamp());

  XCTAssertEqual(self.effect->rampRemaining(), 0);
  XCTAssertEqual(self.effect->treeBasedRampDuration(), rampDuration);

  auto status = self.effect->processAndRender(&timestamp, frames, 0, outputData, nullptr, mockPullInput);
  XCTAssertEqual(status, 0);
  XCTAssertTrue(self.effect->isRamping());
  XCTAssertEqual(self.effect->frameCounts_.size(), 1);
  XCTAssertEqual(self.effect->frameCounts_[0], 512);
  XCTAssertEqual(self.effect->frameCounts_[self.effect->frameCounts_.size() - 1], 512);
  XCTAssertEqual(self.effect->rampRemaining(), 31);
  XCTAssertEqualWithAccuracy(self.effect->param_.frameValue(), 27.562500, 1.0e-6);
  self.effect->frameCounts_.clear();
}

- (void)testRampingDurationClearedOnRenderStateChange {
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AUAudioFrameCount maxFrames = 512;
  AudioTimeStamp timestamp = AudioTimeStamp();
  AUAudioFrameCount frames = maxFrames;
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:maxFrames];
  AudioBufferList *outputData = [buffer mutableAudioBufferList];
  outputData->mBuffers[0].mData = nil;
  outputData->mBuffers[1].mData = nil;

  AUParameterEvent* rampingEvent = new AUParameterEvent();
  rampingEvent->next = nullptr;
  rampingEvent->eventSampleTime = -1;
  rampingEvent->parameterAddress = 1;
  rampingEvent->rampDurationSampleFrames = 4;
  rampingEvent->value = 10;

  AURenderEvent* eventList = reinterpret_cast<AURenderEvent*>(rampingEvent);
  eventList->head.eventType = AURenderEventParameterRamp;

  // Do 2 frames. Should be split into 2 1-frame render calls.
  auto status = self.effect->processAndRender(&timestamp, 2, 0, outputData, eventList, mockPullInput);
  XCTAssertEqual(status, 0);
  XCTAssertEqual(self.effect->frameCounts_.size(), 1);
  XCTAssertEqual(self.effect->frameCounts_[0], 2);

  // Stop / start rendering
  self.effect->deallocateRenderResources();
  [self setRenderingFormat];

  // Do 10 frames. Should be done as 1 10-frame render call.
  status = self.effect->processAndRender(&timestamp, 10, 0, outputData, nullptr, mockPullInput);
  XCTAssertEqual(status, 0);
  XCTAssertEqual(self.effect->frameCounts_.size(), 2);
  XCTAssertEqual(self.effect->frameCounts_[0], 2);
  XCTAssertEqual(self.effect->frameCounts_[1], 10);
}

- (void)testDetectParameterChange {
  self.effect->param_.setPending(123.5);
  XCTAssertEqualWithAccuracy(self.effect->param_.getPending(), 123.5, epsilon);
  XCTAssertEqual(self.effect->param_.getImmediate(), 123.5);
  XCTAssertFalse(self.effect->isRamping());
  self.effect->checkForTreeBasedParameterChanges();
  XCTAssertTrue(self.effect->isRamping());
}

- (void)testRenderDisableClearsRamping {
  self.effect->param_.setPending(123.5);
  self.effect->checkForTreeBasedParameterChanges();
  XCTAssertTrue(self.effect->isRamping());
  self.effect->deallocateRenderResources();
  XCTAssertFalse(self.effect->isRamping());
}

struct MockEffectWithRenderingStateChanged : public EventProcessor<MockEffectWithRenderingStateChanged>
{
  using super = EventProcessor<MockEffectWithRenderingStateChanged>;

  MockEffectWithRenderingStateChanged() : super("mock") { registerParameters({param1_, param2_}); }
  bool isRendering() const { return super::isRendering(); }
  void doRendering(BusBuffers, BusBuffers, AUAudioFrameCount frameCount) {}
  void doRenderingStateChanged(bool rendering) { ++renderingStateChanges_; }
  bool checkForTreeBasedParameterChanges() { return super::checkForParameterValueChanges(); }

  Parameters::Float param1_{0, 0.0};
  Parameters::Float param2_{1, 0.0};
  int renderingStateChanges_{0};
};

ValidatedKernel<MockEffectWithRenderingStateChanged> _mockEffectWithRenderingStateChanged;

- (void)testRenderingStateChanged {
  auto effect = new MockEffectWithRenderingStateChanged();
  XCTAssertEqual(effect->renderingStateChanges_, 0);
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AUAudioFrameCount maxFrames = 512;
  effect->setRenderingFormat(1, format, maxFrames);
  XCTAssertEqual(effect->renderingStateChanges_, 1);
  effect->deallocateRenderResources();
  XCTAssertEqual(effect->renderingStateChanges_, 2);
}

- (void)testRenderingStateChangeClearsRamping {
  auto effect = new MockEffectWithRenderingStateChanged();
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AUAudioFrameCount maxFrames = 512;
  effect->setRenderingFormat(1, format, maxFrames);

  XCTAssertTrue(effect->isRendering());
  XCTAssertEqual(effect->treeBasedRampDuration(), 16);

  effect->setParameterValue(0, 123.45);
  effect->setParameterValue(1, 987);

  XCTAssertTrue(effect->checkForTreeBasedParameterChanges());
  XCTAssertTrue(effect->isRamping());
  XCTAssertEqualWithAccuracy(effect->param1_.frameValue(), 7.715625, 0.00001);
  XCTAssertEqualWithAccuracy(effect->param2_.frameValue(), 61.687500, 0.00001);

  effect->checkForTreeBasedParameterChanges();
  XCTAssertTrue(effect->isRamping());
  XCTAssertEqualWithAccuracy(effect->param1_.frameValue(), 15.431250, 0.00001);
  XCTAssertEqualWithAccuracy(effect->param2_.frameValue(), 123.375000, 0.00001);

  effect->deallocateRenderResources();
  XCTAssertFalse(effect->isRamping());
  XCTAssertEqualWithAccuracy(effect->param1_.frameValue(), 123.45, 0.00001);
  XCTAssertEqualWithAccuracy(effect->param1_.frameValue(), 123.45, 0.00001);
  XCTAssertEqualWithAccuracy(effect->param2_.frameValue(), 987.0, 0.00001);
}

struct MockEffectWithMIDI : public EventProcessor<MockEffectWithMIDI>
{
  using super = EventProcessor<MockEffectWithMIDI>;

  MockEffectWithMIDI() : super("mock") { registerParameter(param_); }

  void doMIDIEvent(const AUMIDIEvent&) { midiEvents_ += 1; }

  void doRendering(BusBuffers, BusBuffers, AUAudioFrameCount frameCount) {}

  Parameters::Float param_{0};
  int midiEvents_{0};
};

- (void)testMIDIEventProcessing {
  auto effect = new MockEffectWithMIDI();
  XCTAssertEqual(effect->midiEvents_, 0);
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AUAudioFrameCount maxFrames = 512;
  effect->setRenderingFormat(1, format, maxFrames);

  AudioTimeStamp timestamp = AudioTimeStamp();
  AUAudioFrameCount frames = maxFrames;
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:maxFrames];
  AudioBufferList *outputData = [buffer mutableAudioBufferList];
  outputData->mBuffers[0].mData = nil;
  outputData->mBuffers[1].mData = nil;

  AUMIDIEvent* midiEvent = new AUMIDIEvent();
  midiEvent->next = nullptr;
  midiEvent->eventSampleTime = -1;

  AURenderEvent* eventList = reinterpret_cast<AURenderEvent*>(midiEvent);
  eventList->head.eventType = AURenderEventMIDI;

  auto status = effect->processAndRender(&timestamp, maxFrames, 0, outputData, eventList, mockPullInput);
  XCTAssertEqual(status, 0);
  XCTAssertEqual(effect->midiEvents_, 1);
}

/// Kernel that derives each output sample from its input sample, so that misaligned input buffers are detectable.
struct MockInputReadingEffect : public EventProcessor<MockInputReadingEffect>
{
  using super = EventProcessor<MockInputReadingEffect>;

  MockInputReadingEffect() : super("mock") { registerParameter(param_); }

  void doRendering(BusBuffers ins, BusBuffers outs, AUAudioFrameCount frameCount) {
    for (size_t channel = 0; channel < outs.size(); ++channel) {
      for (AUAudioFrameCount frame = 0; frame < frameCount; ++frame) {
        outs[channel][frame] = ins[channel][frame] + 1000;
      }
    }
  }

  Parameters::Float param_{1, 0.0};
};

- (void)renderWithMidBlockEvent:(BOOL)inPlace {
  MockInputReadingEffect effect;
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AUAudioFrameCount frames = 512;
  effect.setRenderingFormat(1, format, frames);

  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frames];
  AudioBufferList* outputData = [buffer mutableAudioBufferList];
  if (inPlace) {
    outputData->mBuffers[0].mData = nil;
    outputData->mBuffers[1].mData = nil;
  }

  // An event at frame 100 splits the block into renders of 100 and 412 frames.
  AUParameterEvent event{};
  event.next = nullptr;
  event.eventSampleTime = 100;
  event.parameterAddress = 1;
  event.value = 0.5;
  AURenderEvent* eventList = reinterpret_cast<AURenderEvent*>(&event);
  eventList->head.eventType = AURenderEventParameter;

  AudioTimeStamp timestamp = AudioTimeStamp();
  XCTAssertEqual(effect.processAndRender(&timestamp, frames, 0, outputData, eventList, mockPullInput), 0);

  // `mockPullInput` writes the frame index as each input sample, so every output sample must be its index + 1000.
  // Before the input buffers were offset with the output ones, the second render read the input from frame 0.
  for (UInt32 channel = 0; channel < outputData->mNumberBuffers; ++channel) {
    auto ptr = static_cast<AUValue*>(outputData->mBuffers[channel].mData);
    XCTAssertEqual(ptr[0], 1000.0);
    XCTAssertEqual(ptr[99], 1099.0);
    XCTAssertEqual(ptr[100], 1100.0);
    XCTAssertEqual(ptr[frames - 1], 1000.0 + frames - 1);
  }
}

- (void)testInputAlignedWithOutputAfterMidBlockEvent {
  [self renderWithMidBlockEvent:NO];
}

- (void)testInPlaceInputAlignedWithOutputAfterMidBlockEvent {
  [self renderWithMidBlockEvent:YES];
}

- (void)testBypassWithoutInputEmitsSilence {
  self.effect->setBypass(true);
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AUAudioFrameCount frames = 512;
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frames];
  AudioBufferList* outputData = [buffer mutableAudioBufferList];

  // Stale samples from a previous render must not leak out while bypassed.
  for (UInt32 channel = 0; channel < outputData->mNumberBuffers; ++channel) {
    std::fill_n(static_cast<AUValue*>(outputData->mBuffers[channel].mData), frames, 7.0f);
  }

  // An event at frame 100 splits the block, so both segments must be cleared.
  AUParameterEvent event{};
  event.next = nullptr;
  event.eventSampleTime = 100;
  event.parameterAddress = 1;
  event.value = 0.5;
  AURenderEvent* eventList = reinterpret_cast<AURenderEvent*>(&event);
  eventList->head.eventType = AURenderEventParameter;

  AudioTimeStamp timestamp = AudioTimeStamp();
  XCTAssertEqual(self.effect->processAndRender(&timestamp, frames, 0, outputData, eventList, nullptr), 0);
  XCTAssertTrue(self.effect->frameCounts_.empty());

  for (UInt32 channel = 0; channel < outputData->mNumberBuffers; ++channel) {
    auto ptr = static_cast<AUValue*>(outputData->mBuffers[channel].mData);
    XCTAssertEqual(std::count(ptr, ptr + frames, 0.0f), frames);
  }
}

- (void)testInvalidBufferListReturnsStatus {
  AudioTimeStamp timestamp = AudioTimeStamp();

  // The effect is configured for stereo, so a mono buffer list is rejected instead of terminating the process.
  AVAudioFormat* mono = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:1];
  AVAudioPCMBuffer* monoBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:mono frameCapacity:512];
  XCTAssertEqual(self.effect->processAndRender(&timestamp, 512, 0, [monoBuffer mutableAudioBufferList], nullptr,
                                               mockPullInput),
                 kAudioUnitErr_FormatNotSupported);

  // A stereo list with storage for only one channel is rejected as well.
  AVAudioFormat* stereo = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
  AVAudioPCMBuffer* stereoBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:stereo frameCapacity:512];
  AudioBufferList* partial = [stereoBuffer mutableAudioBufferList];
  partial->mBuffers[1].mData = nil;
  XCTAssertEqual(self.effect->processAndRender(&timestamp, 512, 0, partial, nullptr, mockPullInput),
                 kAudio_ParamError);

  XCTAssertTrue(self.effect->frameCounts_.empty());
}

- (void)testDeallocateTwiceIsSafe {
  self.effect->deallocateRenderResources();
  self.effect->deallocateRenderResources();
  XCTAssertFalse(self.effect->isRendering());
}

@end
