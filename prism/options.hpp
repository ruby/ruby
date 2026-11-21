/**
 * @file options.hpp
 *
 * Ownership of parse options from C++.
 */
#ifndef PRISM_OPTIONS_HPP
#define PRISM_OPTIONS_HPP

#include "prism/compiler/cplusplus.hpp"

#include "prism/options.h"

#include <memory>

namespace prism {

/** Frees options with pm_options_free. */
struct options_deleter {
    /**
     * Free the given options.
     *
     * @param options The options to free.
     */
    void operator()(pm_options_t *options) const noexcept { pm_options_free(options); }
};

/** An owned set of options. */
using unique_options = std::unique_ptr<pm_options_t, options_deleter>;

/**
 * Allocate a new set of options with every option at its default. Allocation
 * failure aborts, so this never throws.
 *
 * @return A unique_options owning the newly allocated options.
 */
[[nodiscard]] inline unique_options
make_options() noexcept {
    return unique_options(pm_options_new());
}

}

#endif
