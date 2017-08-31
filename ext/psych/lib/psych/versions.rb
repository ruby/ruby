# frozen_string_literal: true
module Psych
  # The version is Psych you're using
  VERSION = '3.0.0.beta3'

  if RUBY_ENGINE == 'jruby'
    DEFAULT_SNAKEYAML_VERSION = '1.18'.freeze
  end
end
