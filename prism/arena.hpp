/**
 * @file arena.hpp
 *
 * Ownership of arenas from C++.
 */
#ifndef PRISM_ARENA_HPP
#define PRISM_ARENA_HPP

#include "prism/compiler/cplusplus.hpp"

#include "prism/arena.h"

#include <memory>

namespace prism {

/** Frees an arena with pm_arena_free. */
struct arena_deleter {
    /**
     * Frees the given arena.
     *
     * @param arena The arena to free.
     */
    void operator()(pm_arena_t *arena) const noexcept { pm_arena_free(arena); }
};

/** An owned arena. */
using unique_arena = std::unique_ptr<pm_arena_t, arena_deleter>;

/**
 * Allocate a new arena. Allocation failure aborts, so this never throws.
 *
 * @return A unique_arena managing the newly allocated arena.
 */
[[nodiscard]] inline unique_arena
make_arena() noexcept {
    return unique_arena(pm_arena_new());
}

}

#endif
