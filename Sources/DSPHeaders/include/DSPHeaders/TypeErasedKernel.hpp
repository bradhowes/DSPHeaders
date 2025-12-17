// Copyright © 2024-2025 Brad Howes. All rights reserved.

#pragma once

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#import <functional>

namespace DSPHeaders {

/**
   The Swift/C++ bridge has (had?) some issues with mapping `AUInternalRenderBlock` into Swift. The following works
   around the issue by type-erasing the `AUInternalRenderBlock` invocation via a `std::function` value that is later
   invoked via a shim.
 */
struct TypeErasedKernel
{
  using ProcessAndRender = std::function<AUAudioUnitStatus(const AudioTimeStamp*,
                                                           UInt32,
                                                           NSInteger,
                                                           AudioBufferList*,
                                                           const AURenderEvent*,
                                                           AURenderPullInputBlock)>;
  TypeErasedKernel() : processAndRender_{} {}

  TypeErasedKernel(ProcessAndRender par) : processAndRender_{par} {}

  std::function<AUAudioUnitStatus(const AudioTimeStamp*, UInt32, NSInteger, AudioBufferList*, const AURenderEvent*,
                                  AURenderPullInputBlock)> processAndRender_;
};

struct RenderBlockShim
{
  RenderBlockShim(TypeErasedKernel kernel) : kernel_{kernel} {}

  AUInternalRenderBlock internalRenderBlock() {
    if (kernel_.processAndRender_) {
      __block auto proc = kernel_.processAndRender_;
      return ^AUAudioUnitStatus(
        AudioUnitRenderActionFlags*,
        const AudioTimeStamp* timestamp,
        AVAudioFrameCount frameCount,
        NSInteger outputBusNumber,
        AudioBufferList* outputData,
        const AURenderEvent* realtimeEventListHead,
        AURenderPullInputBlock __unsafe_unretained pullInputBlock) {
        return proc(timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock);
      };
    } else {
      return ^AUAudioUnitStatus(AudioUnitRenderActionFlags*,
                                const AudioTimeStamp*,
                                AVAudioFrameCount,
                                NSInteger,
                                AudioBufferList*,
                                const AURenderEvent*,
                                AURenderPullInputBlock __unsafe_unretained) {
        return -1;
      };
    }
  }

  TypeErasedKernel kernel_;
};

}
