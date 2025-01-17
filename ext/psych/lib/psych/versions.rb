# frozen_string_literal: true

module Psych
  # The version of Psych you are using
  VERSION = '5.2.3'

  if RUBY_ENGINE == 'jruby'
    DEFAULT_SNAKEYAML_VERSION = '2.9'.freeze
  end
end
