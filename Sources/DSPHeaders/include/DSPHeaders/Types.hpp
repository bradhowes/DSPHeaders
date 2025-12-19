// Copyright © 2024-2025 Brad Howes. All rights reserved.

#import <type_traits>

#import "DSPHeaders/Concepts.hpp"

namespace DSPHeaders {

/**
 Convert an enum value into its underlying integral type.
 */
template <EnumeratedType T>
constexpr auto valueOf(T index) noexcept { return static_cast<typename std::underlying_type<T>::type>(index); };

/// Literal operator that generates `Float` values from the literal content.
constexpr double operator ""_F(long double value) { return double(value); }

/// Literal operator that generates `Float` values from the literal content.
constexpr double operator ""_F(unsigned long long value) { return double(value); }

/**
 Generic method that invokes checked or unchecked indexing on a container based on the DEBUG compile flag. When DEBUG
 is defined, invokes `at` which will validate the index prior to use, and as a result is slower than just blindly
 indexing via `operator []`.
 */
template <RandomAccessContainer T>
const typename T::value_type& checkedVectorIndexing(const T& container, size_t index) noexcept
{
#if defined(CHECKED_VECTOR_INDEXING) && CHECKED_VECTOR_INDEXING == 1
  return container.at(index);
#else
  return container[index];
#endif
}

/// Allow for safe indexing into a `vector` when enabled with `CHECKED_VECTOR_INDEXING` set to `1`.
template <RandomAccessContainer T, SizableType S>
const typename T::value_type& checkedVectorIndexing(const T& container, S index) noexcept
{
  auto index_ = static_cast<size_t>(index);
#if defined(CHECKED_VECTOR_INDEXING) && CHECKED_VECTOR_INDEXING == 1
  return container.at(index_);
#else
  return container[index_];
#endif
}

template <RandomAccessContainer T, SizableType S>
typename T::value_type& checkedVectorIndexing(T& container, S index) noexcept
{
  auto index_ = static_cast<size_t>(index);
#if defined(CHECKED_VECTOR_INDEXING) && CHECKED_VECTOR_INDEXING == 1
  return container.at(index_);
#else
  return container[index_];
#endif
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
