// Copyright © 2021-2026 Brad Howes. All rights reserved.

#pragma once

#include <type_traits>

#include <os/log.h>
#include <AudioToolbox/AUAudioUnit.h>
#include <algorithm>
#include <span>
#include <vector>

#include "DSPHeaders/Accelerated.hpp"
#include "DSPHeaders/BusBuffers.hpp"

namespace DSPHeaders {

/**
 Provides a simple view of an N-channel `AudioBufferList` as a vector of `AUValue` pointers. This is much easier to work
 with in a kernel than an `AudioBufferList` instance. In `EventProcessor`, the `AudioBufferList` value comes from a
 `BusSampleBuffer` instance, but this is not required here.

 Supports in-place rendering where the input buffer is used for rendering and is overwritten with output samples.
 */
struct BusBufferFacet {
  /**
   Construct a new instance.
   */
  BusBufferFacet() noexcept {}

  /**
   Set the expected number of channels to support during rendering. The goal is to not encounter any memory
   allocations while rendering, so this *must* be called before rendering is started.

   @param channelCount the number of channels to expect
   */
  void setChannelCount(AUAudioChannelCount channelCount) noexcept {
    pointers_.reserve(channelCount);
    pointers_.resize(channelCount);
  }

  /**
   Set the underlying buffers to use to hold and report out data. This is to be run within a render thread and will not
   allocate any memory. There are two options:

   - bufferList has non-nullptr mData values -- use it as-is
   - bufferList has nullptr mData values && inPlaceSource != nullptr -- use the inPlaceSource mData elements

   The method fails if the channel count of either `bufferList` or `inPlaceSource` does not match the expected channel
   count, if `bufferList` has a mix of nullptr and non-nullptr mData values, or if a buffer that would be used for
   storage has a nullptr mData value. It reports failure by status rather than by exception because it runs on the
   render thread. All validation takes place before any state is changed, so on failure the facet and `bufferList` are
   left as they were.

   @param bufferList the collection of buffers to use
   @param inPlaceSource if not nullptr, use their mData elements for storage
   @returns `noErr` on success, `kAudioUnitErr_FormatNotSupported` for a channel count mismatch, or `kAudio_ParamError`
   for a missing buffer list or missing storage
   */
  [[nodiscard]] AUAudioUnitStatus assignBufferList(AudioBufferList* bufferList,
                                                   AudioBufferList* inPlaceSource = nullptr) noexcept {
    if (bufferList == nullptr) [[unlikely]] return kAudio_ParamError;

    size_t numBuffers = bufferList->mNumberBuffers;
    if (numBuffers != pointers_.size()) [[unlikely]] return kAudioUnitErr_FormatNotSupported;

    bool inPlace = numBuffers > 0 && bufferList->mBuffers[0].mData == nullptr;
    if (inPlace) {
      // The given bufferList does not have space to use -- attempt to perform in-place rendering.
      if (inPlaceSource == nullptr) [[unlikely]] return kAudio_ParamError;
      if (inPlaceSource->mNumberBuffers != numBuffers) [[unlikely]] return kAudioUnitErr_FormatNotSupported;
      if (!allBuffersMatch(inPlaceSource, true)) [[unlikely]] return kAudio_ParamError;
    }

    // Every buffer in `bufferList` must agree with the first one: all nullptr for in-place rendering, otherwise all
    // non-nullptr.
    if (!allBuffersMatch(bufferList, !inPlace)) [[unlikely]] return kAudio_ParamError;

    if (inPlace) {
      for (UInt32 channel = 0; channel < numBuffers; ++channel) {
        bufferList->mBuffers[channel].mData = inPlaceSource->mBuffers[channel].mData;
      }
    }

    bufferList_ = bufferList;
    setOffset(0);
    return noErr;
  }

  /**
   Set the facet to start at the given offset into the source buffers. Once done, the std::vector AUValue
   pointers will start `offset` samples into the underlying buffer. Does nothing if the facet is not linked.

   @param offset number of samples to offset.
   */
  void setOffset(AUAudioFrameCount offset) noexcept {
    if (!isLinked()) [[unlikely]] return;
    for (size_t channel = 0; channel < pointers_.size(); ++channel) {
      pointers_[channel] = getBufferPointer(channel, offset);
    }
  }

  /**
   Set the number of frames (samples) that are in each buffer. This must be done before the underlying buffers are
   returned to Apple's audio engine that is driving the rendering. Does nothing if the facet is not linked.

   @param frameCount number of samples in a buffer.
   */
  void setFrameCount(AUAudioFrameCount frameCount) noexcept {
    if (!isLinked()) [[unlikely]] return;
    UInt32 byteSize = frameCount * sizeof(AUValue);
    for (UInt32 channel = 0; channel < bufferList_->mNumberBuffers; ++channel) {
      bufferList_->mBuffers[channel].mDataByteSize = byteSize;
    }
  }

  /// @returns true if the facet is linked to a buffer
  bool isLinked() const noexcept { return bufferList_ != nullptr; }

  /**
   Release the underlying buffers. Safe to call when the facet is not linked.
   */
  void unlink() noexcept {
    bufferList_ = nullptr;
    for (size_t channel = 0; channel < pointers_.size(); ++channel) {
      pointers_[channel] = nullptr;
    }
  }

  /**
   Obtain samples from an upstream node. Output is stored in the AudioBufferList that was installed by `setBufferList`.

   @param actionFlags render flags from the host
   @param timestamp the current transport time of the samples
   @param frameCount the number of frames to process
   @param inputBusNumber the bus to pull from
   @param pullInputBlock the function to call to do the pulling
   @returns status from `pullInputBlock`, or an error if there is no block, the facet is not linked, or the buffers
   are too small
   */
  AUAudioUnitStatus pullInput(AudioUnitRenderActionFlags* actionFlags, AudioTimeStamp const* timestamp,
                              AUAudioFrameCount frameCount, NSInteger inputBusNumber,
                              AURenderPullInputBlock pullInputBlock) noexcept {
    if (pullInputBlock == nullptr) [[unlikely]] {
      return kAudioUnitErr_NoConnection;
    }

    if (!isLinked()) [[unlikely]] return kAudioUnitErr_Uninitialized;
    if (frameCount * sizeof(AUValue) > bufferList_->mBuffers[0].mDataByteSize) [[unlikely]] {
      return kAudioUnitErr_TooManyFramesToProcess;
    }

    setFrameCount(frameCount);
    return pullInputBlock(actionFlags, timestamp, frameCount, inputBusNumber, bufferList_);
  }

  /**
   Copy contents of the buffers into the given destination, starting at the offset and copying frameCount bytes.
   Currently this is only used when an audio unit is in bypass mode. Does nothing unless both facets are linked.

   @param destination the buffer to copy into
   @param offset the offset to apply before writing
   @param frameCount the number of samples to write
   */
  void copyInto(BusBufferFacet& destination, AUAudioFrameCount offset, AUAudioFrameCount frameCount) const noexcept {
    if (!isLinked() || !destination.isLinked()) [[unlikely]] return;
    auto outputs = destination.bufferList_;
    for (UInt32 channel = 0; channel < bufferList_->mNumberBuffers; ++channel) {
      if (bufferList_->mBuffers[channel].mData == outputs->mBuffers[channel].mData) {
        // nothing to do since input buffer is being used for output buffer (in-place rendering).
        continue;
      }
      auto in = getBufferPointer(channel, offset);
      auto out = destination.getBufferPointer(channel, offset);
      std::copy_n(in, frameCount, out);
    }
  }

  /**
   Set the sample values to zero for the next N frames. This is used when there is no upstream node to pull from.

   @param frameCount the number of frames to clear
   */
  void clear(AUAudioFrameCount frameCount) noexcept {
    if (!isLinked()) [[unlikely]] return;
    constexpr auto stride = vDSP_Stride(1);
    auto length = vDSP_Length(frameCount);
    for (UInt32 channel = 0; channel < bufferList_->mNumberBuffers; ++channel) {
      Accelerated<AUValue>::zeroProc(getBufferPointer(channel, 0), stride, length);
    }
  }

  /// @returns the number of channels that are currently supported
  size_t channelCount() const noexcept { return pointers_.size(); }

  /// @returns new BusBuffers instance that refers to our collection of AUValue pointers for storing render samples.
  BusBuffers busBuffers() noexcept {
    return BusBuffers(pointers_);
  }

private:
  AUValue* getBufferPointer(size_t channel, AUAudioFrameCount offset) const noexcept {
    return static_cast<AUValue*>(bufferList_->mBuffers[channel].mData) + offset;
  }

  /**
   Check that every buffer in a list agrees on whether it has storage.

   @param bufferList the collection of buffers to check
   @param hasData true if every mData value must be non-nullptr, false if every mData value must be nullptr
   @returns true if every buffer matches `hasData`
   */
  static bool allBuffersMatch(const AudioBufferList* bufferList, bool hasData) noexcept {
    for (UInt32 channel = 0; channel < bufferList->mNumberBuffers; ++channel) {
      if ((bufferList->mBuffers[channel].mData != nullptr) != hasData) {
        return false;
      }
    }
    return true;
  }

  AudioBufferList* bufferList_{nullptr};
  std::vector<AUValue*> pointers_{};
};

} // end namespace DSPHeaders
