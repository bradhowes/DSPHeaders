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

}
