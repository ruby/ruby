# frozen_string_literal: false
module Psych
  # The version is Psych you're using
  VERSION = '2.2.3'

  if RUBY_ENGINE == 'jruby'
    DEFAULT_SNAKEYAML_VERSION = '1.18'.freeze
  end
end
