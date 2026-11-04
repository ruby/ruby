/**
 * @file buffer.hpp
 *
 * Ownership of buffers from C++, and access to their contents.
 */
#ifndef PRISM_BUFFER_HPP
#define PRISM_BUFFER_HPP

#include "prism/compiler/cplusplus.hpp"
#include "prism/compiler/lifetimebound.hpp"

#include "prism/buffer.h"

#include <memory>
#include <string_view>

namespace prism {

/** Frees a buffer with pm_buffer_free. */
struct buffer_deleter {
    /**
     * Frees the given buffer.
     *
     * @param buffer The buffer to free.
     */
    void operator()(pm_buffer_t *buffer) const noexcept { pm_buffer_free(buffer); }
};

/** An owned buffer. */
using unique_buffer = std::unique_ptr<pm_buffer_t, buffer_deleter>;

/**
 * Allocate a new empty buffer. Allocation failure aborts, so this never throws.
 *
 * @return A unique_buffer managing the newly allocated buffer.
 */
[[nodiscard]] inline unique_buffer
make_buffer() noexcept {
    return unique_buffer(pm_buffer_new());
}

/**
 * The bytes written to the given buffer so far.
 *
 * @param buffer The buffer to view.
 * @return A string_view of the contents of the buffer.
 */
[[nodiscard]] inline std::string_view
view(const pm_buffer_t *buffer PRISM_LIFETIMEBOUND) noexcept {
    return std::string_view(pm_buffer_value(buffer), pm_buffer_length(buffer));
}

}

#endif
