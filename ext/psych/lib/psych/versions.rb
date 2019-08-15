
# frozen_string_literal: true
module Psych
  # The version of Psych you are using
  VERSION = '3.1.0' unless defined?(::Psych::VERSION)

  if RUBY_ENGINE == 'jruby'
    DEFAULT_SNAKEYAML_VERSION = '1.23'.freeze
  end
end
