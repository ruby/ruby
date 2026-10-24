/**
 * @file parser.hpp
 *
 * Ownership of parsers from C++, and lookups through a parser into the source,
 * the constant pool, comments, and diagnostics.
 */
#ifndef PRISM_PARSER_HPP
#define PRISM_PARSER_HPP

#include "prism/compiler/cplusplus.hpp"
#include "prism/compiler/lifetimebound.hpp"

#include "prism/arena.h"
#include "prism/constant_pool.h"
#include "prism/line_offset_list.h"
#include "prism/parser.h"

#include <cassert>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <memory>
#include <string_view>

namespace prism {

/** Frees a parser with pm_parser_free. */
struct parser_deleter {
    /**
     * Free the given parser.
     *
     * @param parser The parser to free.
     */
    void operator()(pm_parser_t *parser) const noexcept { pm_parser_free(parser); }
};

/** An owned parser. */
using unique_parser = std::unique_ptr<pm_parser_t, parser_deleter>;

/**
 * Allocate a new parser over the given source. The source, the arena, and the
 * options (which may be null) are not copied, so all three must outlive the
 * parser. Allocation failure aborts, so this never throws.
 *
 * @param arena The arena to use for allocations.
 * @param source The source code to parse.
 * @param options The parse options, or null for defaults.
 * @return A unique_parser owning the newly allocated parser.
 */
[[nodiscard]] inline unique_parser
make_parser(pm_arena_t *arena PRISM_LIFETIMEBOUND, std::string_view source PRISM_LIFETIMEBOUND, const pm_options_t *options PRISM_LIFETIMEBOUND = nullptr) noexcept {
    return unique_parser(pm_parser_new(arena, reinterpret_cast<const std::uint8_t *>(source.data()), source.size(), options));
}

/**
 * The name of the constant with the given id, which must not be zero. Fields
 * holding an optional constant use zero for none, so check those first.
 *
 * @param parser The parser containing the constant.
 * @param constant_id The id of the constant.
 * @return The value of the constant.
 */
[[nodiscard]] inline std::string_view
constant(const pm_parser_t *parser PRISM_LIFETIMEBOUND, pm_constant_id_t constant_id) noexcept {
    assert(constant_id != 0);
    const pm_constant_t *entry = pm_parser_constant(parser, constant_id);
    return std::string_view(reinterpret_cast<const char *>(pm_constant_start(entry)), pm_constant_length(entry));
}

/**
 * The bytes of source that the given location covers.
 *
 * @param parser The parser containing the source.
 * @param location The location in the source.
 * @return The bytes of source covered by the location.
 */
[[nodiscard]] inline std::string_view
slice(const pm_parser_t *parser PRISM_LIFETIMEBOUND, pm_location_t location) noexcept {
    return std::string_view(reinterpret_cast<const char *>(pm_parser_start(parser) + location.start), location.length);
}

/**
 * The line and column of the given byte offset into the source. Lines start at
 * the parser's start line, and columns are byte offsets from the line start.
 *
 * @param parser The parser containing the source.
 * @param offset The byte offset into the source.
 * @return The line and column of the byte offset.
 */
[[nodiscard]] inline pm_line_column_t
line_column(const pm_parser_t *parser, std::uint32_t offset) noexcept {
    return pm_line_offset_list_line_column(pm_parser_line_offsets(parser), offset, pm_parser_start_line(parser));
}

namespace detail {

/**
 * The diagnostics, comments, or magic comments found while parsing, usable in a
 * range-based for loop and with the standard algorithms. Each element is a
 * pointer to the C struct, which the C accessors read, and Next is the C
 * function that returns the item after a given one. It refers to the parser
 * rather than copying from it, so the parser must outlive it. It is used
 * through diagnostic_range, comment_range, and magic_comment_range.
 */
template <typename T, const T *(*Next)(const T *)> class next_range {
public:
    /** Steps through the items one after another. */
    class iterator {
    public:
        /** The iterator category, for the standard algorithms. */
        using iterator_category = std::forward_iterator_tag;

        /** The type of each element. */
        using value_type = const T *;

        /** The type of the distance between two iterators. */
        using difference_type = std::ptrdiff_t;

        /** The type of a pointer to an element. */
        using pointer = const value_type *;

        /** The type of a reference to an element. */
        using reference = const value_type &;

        /** Create the iterator that marks the end of the items. */
        iterator() noexcept = default;

        /**
         * Create an iterator at the given item.
         *
         * @param current The current item.
         */
        explicit iterator(const T *current) noexcept : current_(current) {}

        /**
         * The item at this position, which must not be the end.
         *
         * @return The current item.
         */
        reference operator*() const noexcept { return current_; }

        /**
         * Advance to the next item.
         *
         * @return The iterator after advancing.
         */
        iterator &
        operator++() noexcept {
            assert(current_ != nullptr);
            current_ = Next(current_);
            return *this;
        }

        /**
         * Advance to the next item, returning the iterator from before.
         *
         * @return The iterator from before advancing.
         */
        iterator
        operator++(int) noexcept {
            iterator previous = *this;
            ++*this;
            return previous;
        }

        /** Whether the two iterators are at the same item. */
        friend bool operator==(iterator left, iterator right) noexcept { return left.current_ == right.current_; }

        /** Whether the two iterators are at different items. */
        friend bool operator!=(iterator left, iterator right) noexcept { return left.current_ != right.current_; }

    private:
        const T *current_ = nullptr;
    };

    /**
     * Create a range of the given number of items starting at first.
     *
     * @param first The first item.
     * @param size The number of items.
     */
    next_range(const T *first, std::size_t size) noexcept : first_(first), size_(size) {}

    /**
     * An iterator at the first item.
     *
     * @return An iterator at the first item.
     */
    iterator begin() const noexcept { return iterator(first_); }

    /**
     * An iterator past the last item.
     *
     * @return An iterator past the last item.
     */
    iterator end() const noexcept { return iterator(); }

    /**
     * The number of items.
     *
     * @return The number of items.
     */
    std::size_t size() const noexcept { return size_; }

    /**
     * Whether there are no items.
     *
     * @return Whether there are no items.
     */
    [[nodiscard]] bool empty() const noexcept { return size_ == 0; }

private:
    const T *first_;
    std::size_t size_;
};

}

/** The errors or warnings found while parsing. */
using diagnostic_range = detail::next_range<pm_diagnostic_t, pm_diagnostic_next>;

/** The comments found while parsing. */
using comment_range = detail::next_range<pm_comment_t, pm_comment_next>;

/** The magic comments found while parsing. */
using magic_comment_range = detail::next_range<pm_magic_comment_t, pm_magic_comment_next>;

/**
 * The errors found while parsing.
 *
 * @param parser The parser containing the source.
 * @return The range of errors found while parsing.
 */
[[nodiscard]] inline diagnostic_range
errors(const pm_parser_t *parser PRISM_LIFETIMEBOUND) noexcept {
    return diagnostic_range(pm_parser_errors_first(parser), pm_parser_errors_size(parser));
}

/**
 * The warnings found while parsing.
 *
 * @param parser The parser containing the source.
 * @return The range of warnings found while parsing.
 */
[[nodiscard]] inline diagnostic_range
warnings(const pm_parser_t *parser PRISM_LIFETIMEBOUND) noexcept {
    return diagnostic_range(pm_parser_warnings_first(parser), pm_parser_warnings_size(parser));
}

/**
 * The comments found while parsing, in source order.
 *
 * @param parser The parser containing the source.
 * @return The range of comments found while parsing.
 */
[[nodiscard]] inline comment_range
comments(const pm_parser_t *parser PRISM_LIFETIMEBOUND) noexcept {
    return comment_range(pm_parser_comments_first(parser), pm_parser_comments_size(parser));
}

/**
 * The magic comments found while parsing.
 *
 * @param parser The parser containing the source.
 * @return The range of magic comments found while parsing.
 */
[[nodiscard]] inline magic_comment_range
magic_comments(const pm_parser_t *parser PRISM_LIFETIMEBOUND) noexcept {
    return magic_comment_range(pm_parser_magic_comments_first(parser), pm_parser_magic_comments_size(parser));
}

}

#endif
