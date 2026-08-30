# frozen_string_literal: true

##
# Gem::ContentAddress encapsulates the pattern for recognizing
# content-addressable gem file names.

module Gem::ContentAddress
  # :nodoc:
  PATTERN = /\A[0-9a-f]{8,64}\z/

  ##
  # Whether +spec+ is eligible for content addressing. A gem must
  # pin a required_ruby_version and declare a non-RUBY platform to be
  # content addressed.

  def self.applicable?(spec)
    required_ruby_version = spec.required_ruby_version
    !required_ruby_version.nil? && !required_ruby_version.none? &&
      !spec.platform.nil? && spec.platform != Gem::Platform::RUBY
  end

  ##
  # Whether +spec+ is content-addressed: it is eligible for content
  # addressing and has a valid content address set.

  def self.content_addressed?(spec)
    applicable?(spec) && match?(spec.content_address)
  end

  ##
  # Whether +value+ is a valid content address (a string of 8-64
  # lowercase hexadecimal characters).

  def self.match?(value)
    value.is_a?(String) && PATTERN.match?(value)
  end

  ##
  # Ranks +spec+ for candidate selection against +ruby_version+: a
  # content-addressed spec built for that Ruby ranks first (0), any
  # non-content-addressed spec next (1), and a content-addressed spec built
  # for another Ruby last (2), since its binary cannot load there.

  def self.ruby_abi_specificity_match(spec, ruby_version = Gem.ruby_version)
    return 1 unless match?(spec.content_address)

    if spec.required_ruby_version.satisfied_by?(ruby_version)
      0
    else
      2
    end
  end
end
