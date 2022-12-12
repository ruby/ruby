# frozen_string_literal: true

module Psych
  # The version of Psych you are using
  VERSION = '5.0.1'

  if RUBY_ENGINE == 'jruby'
    DEFAULT_SNAKEYAML_VERSION = '1.33'.freeze
  end
end
