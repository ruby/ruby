/**
 * @file stringy.hpp
 *
 * Access to the contents of strings from C++.
 */
#ifndef PRISM_STRINGY_HPP
#define PRISM_STRINGY_HPP

#include "prism/compiler/cplusplus.hpp"
#include "prism/compiler/lifetimebound.hpp"

#include "prism/stringy.h"

#include <string_view>

namespace prism {

/**
 * The bytes of the given string.
 *
 * @param string The string to view.
 * @return A view of the bytes of the string.
 */
[[nodiscard]] inline std::string_view
view(const pm_string_t &string PRISM_LIFETIMEBOUND) noexcept {
    return std::string_view(reinterpret_cast<const char *>(pm_string_source(&string)), pm_string_length(&string));
}

}

#endif
