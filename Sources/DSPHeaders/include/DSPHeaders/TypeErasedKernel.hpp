// Copyright © 2024-2025 Brad Howes. All rights reserved.

#pragma once

#include <AudioToolbox/AudioToolbox.h>
#include <AVFoundation/AVFoundation.h>

#include <functional>
#include <utility>

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

  /// Takes the callable by value and moves it into place, so callers passing a temporary or `std::move` avoid a copy.
  explicit TypeErasedKernel(ProcessAndRender par) : processAndRender_{std::move(par)} {}

  ProcessAndRender processAndRender_;
};

struct RenderBlockShim
{
  /// Takes the kernel by value and moves it into place, so callers passing a temporary or `std::move` avoid a copy.
  explicit RenderBlockShim(TypeErasedKernel kernel) : kernel_{std::move(kernel)} {}

  /**
   Obtain a render block that invokes the kernel's `processAndRender_`. The block holds its own copy of the callable,
   so it remains valid after this shim is destroyed.

   @returns render block for the audio unit, which returns `kAudioUnitErr_Uninitialized` if there is no kernel
   */
  AUInternalRenderBlock internalRenderBlock() {
    if (kernel_.processAndRender_) {
      // Captured by value (copied into the block), not by reference to this shim, which may not outlive the block.
      auto proc = kernel_.processAndRender_;
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
        return kAudioUnitErr_Uninitialized;
      };
    }
  }

  TypeErasedKernel kernel_;
};

}
