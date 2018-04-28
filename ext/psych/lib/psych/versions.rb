# frozen_string_literal: true
module Psych
  # The version is Psych you're using
  VERSION = '3.0.3.pre1'

  if RUBY_ENGINE == 'jruby'
    DEFAULT_SNAKEYAML_VERSION = '1.21'.freeze
  end
end
