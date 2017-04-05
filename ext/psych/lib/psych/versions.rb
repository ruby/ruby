# frozen_string_literal: false
module Psych
  # The version is Psych you're using
  VERSION = '3.0.0.beta1'

  if RUBY_ENGINE == 'jruby'
    DEFAULT_SNAKEYAML_VERSION = '1.18'.freeze
  end
end
