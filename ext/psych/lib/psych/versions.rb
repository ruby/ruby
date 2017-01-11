# frozen_string_literal: false
module Psych
  # The version is Psych you're using
  VERSION = '2.2.2'

  if RUBY_ENGINE == 'jruby'
    DEFAULT_SNAKEYAML_VERSION = '1.17'.freeze
  end
end
