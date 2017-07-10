# frozen_string_literal: true

# Ruby 1.9.3 and old RubyGems don't play nice with frozen version strings
# rubocop:disable MutableConstant

module Bundler
  # We're doing this because we might write tests that deal
  # with other versions of bundler and we are unsure how to
  # handle this better.
  VERSION = "1.14.3" unless defined?(::Bundler::VERSION)
end
