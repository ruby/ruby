# frozen_string_literal: true
module Psych
  # The version is Psych you're using
  VERSION = '3.1.0.pre1' unless defined?(::Psych::VERSION)

  if RUBY_ENGINE == 'jruby'
    DEFAULT_SNAKEYAML_VERSION = '1.21'.freeze
  end
end
