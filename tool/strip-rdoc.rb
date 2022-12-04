#!ruby
# frozen_string_literal: true

# Filter for preventing Doxygen from processing RDoc comments.
# Used by the Doxygen template.

print ARGF.binmode.read.tap {|src|
  src.gsub!(%r|(/\*[!*])(?:(?!\*/).)+?^\s*\*\s?\-\-\s*$(.+?\*/)|m) {
    marker = $1
    comment = $2
    comment.sub!(%r|^\s*\*\s?\+\+\s*$.+?(\s*\*/)\z|m, '\\1')
    marker + comment
  }
}
