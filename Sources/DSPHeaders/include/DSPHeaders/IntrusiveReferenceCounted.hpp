// Copyright © 2024-2026 Brad Howes. All rights reserved.

#pragma once

#include <atomic>

namespace DSPHeaders {

/**
 Manager of a reference counter for an instance of a class T. Used when importing C++ classes as Swift reference
 types. T must derive from `IntrusiveReferenceCounted<T>` and be allocated with `new`.

 Retain and release operations may be performed concurrently from multiple threads.
 */
template<class T>
class IntrusiveReferenceCounted {
public:
  /// Construct instance with initial reference count
  IntrusiveReferenceCounted() : intrusiveReferenceCounter_(1) {}

  /// Increment the reference count for the instance.
  void instrusiveReferenceCountedRetain() noexcept {
    // A new reference can only be created from an existing one, so no ordering is needed here.
    intrusiveReferenceCounter_.fetch_add(1, std::memory_order_relaxed);
  }

  /// Decrement the reference count for the instance. If this releases the last reference then delete the instance.
  void instrusiveReferenceCountedRelease() noexcept {
    // Release ordering publishes this thread's writes to the object; acquire ordering makes the writes of all other
    // releasing threads visible to the thread that deletes it.
    if (intrusiveReferenceCounter_.fetch_sub(1, std::memory_order_acq_rel) == 1) {
      // Delete as the derived type, since this base class does not have a virtual destructor.
      delete static_cast<T*>(this);
    }
  }

  /// @returns the current reference count. Only meaningful when no other thread is changing it.
  int intrusiveReferenceCount() const noexcept { return intrusiveReferenceCounter_.load(std::memory_order_relaxed); }

private:
  std::atomic<int> intrusiveReferenceCounter_;
};

}
