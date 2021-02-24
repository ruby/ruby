
# frozen_string_literal: true
module Psych
  # The version of Psych you are using
  VERSION = '3.3.1'

  if RUBY_ENGINE == 'jruby'
    DEFAULT_SNAKEYAML_VERSION = '1.28'.freeze
  end
end
