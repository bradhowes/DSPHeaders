// Copyright © 2024-2026 Brad Howes. All rights reserved.

#pragma once

#include <array>
#include <type_traits>
#include <utility>

#include "DSPHeaders/Concepts.hpp"

namespace DSPHeaders {

/**
 Convert an enum value into its underlying integral type. This is C++23's `std::to_underlying`, kept under this name
 for existing callers.

 @param index the enum value to convert
 @returns the value as the enum's underlying type
 */
template <EnumeratedType T>
constexpr auto valueOf(T index) noexcept { return std::to_underlying(index); }

/// Literal operator that generates `Float` values from the literal content.
constexpr long double operator ""_F(long double value) { return value; }

/// Literal operator that generates `Float` values from the literal content.
constexpr long double operator ""_F(unsigned long long value) { return value; }

/// True if `checkedVectorIndexing` validates indices, which is enabled by defining `CHECKED_VECTOR_INDEXING=1`. Because
/// this header is part of a Clang module, define it as a compiler flag for the whole build rather than with a `#define`
/// before including the header.
#if defined(CHECKED_VECTOR_INDEXING) && CHECKED_VECTOR_INDEXING == 1
inline constexpr bool checkedVectorIndexingEnabled = true;
#else
inline constexpr bool checkedVectorIndexingEnabled = false;
#endif

/**
 Generic method that invokes checked or unchecked indexing on a container based on the `CHECKED_VECTOR_INDEXING`
 compile flag. When checking is enabled it invokes `at`, which validates the index and throws `std::out_of_range` for an
 invalid one, so the method is `noexcept` only when checking is disabled. Otherwise it indexes with `operator []`, which
 is faster but does not validate.

 @param container the container to index
 @param index the index of the element to return
 @returns reference to the element at `index`
 */
template <RandomAccessContainer T, SizableType S>
const typename T::value_type& checkedVectorIndexing(const T& container, S index)
noexcept(!checkedVectorIndexingEnabled)
{
  auto index_ = static_cast<size_t>(index);
  if constexpr (checkedVectorIndexingEnabled) return container.at(index_);
  else return container[index_];
}

/**
 Generic method that invokes checked or unchecked indexing on a container based on the `CHECKED_VECTOR_INDEXING`
 compile flag. See the `const` version above.

 @param container the container to index
 @param index the index of the element to return
 @returns updatable reference to the element at `index`
 */
template <RandomAccessContainer T, SizableType S>
typename T::value_type& checkedVectorIndexing(T& container, S index) noexcept(!checkedVectorIndexingEnabled)
{
  auto index_ = static_cast<size_t>(index);
  if constexpr (checkedVectorIndexingEnabled) return container.at(index_);
  else return container[index_];
}

/**
 Fixed-size array with template value type that can use an enum for indices.
 */
template <typename ElementType, EnumeratedType EnumType, size_t Size>
class EnumIndexableValueArray : public std::array<ElementType, Size>
{
  using super = std::array<ElementType, Size>;

public:
  /**
   Set all values in the array to the default value for the template type.
   */
  void zero() {
    this->fill(ElementType());
  }

  /**
   Obtain the value at the given index

   @param index the location of the value to return
   @returns the value at the give index
   */
  inline typename super::const_reference operator[](EnumType index) const noexcept {
    return super::operator[](static_cast<size_t>(valueOf(index)));
  }

  inline typename super::const_reference operator[](size_t index) const noexcept {
    return super::operator[](index);
  }

  /**
   Obtain a reference to the value at the given index

   @param index the location of the value to return
   @returns an updatable reference for the given index
   */
  inline typename super::reference& operator[](EnumType index) noexcept {
    return super::operator[](static_cast<size_t>(valueOf(index)));
  }

  inline typename super::reference& operator[](size_t index) noexcept {
    return super::operator[](index);
  }
};

/**
 Convert a boolean value into an AUValue (float)

 @param value the value to convert
 @returns 1.0 for `true` and 0.0 for `false`
 */
template <typename T>
AUValue fromBool(T value) {
  static_assert(std::is_same_v<T, bool>);
  return value ? 1.0 : 0.0;
}

/**
 Convert an AUValue (float) into a boolean value

 @param value the value to convert
 @returns 1.0 for `true` and 0.0 for `false`
 */
template <typename T>
bool toBool(T value) {
  static_assert(std::is_same_v<T, AUValue>);
  return value >= 0.5;
}

}
