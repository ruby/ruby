# frozen_string_literal: true

require 'json/common'

module JSON
  # This module holds all the modules/classes that implement JSON's
  # functionality as C extensions.
  module Ext
    if RUBY_ENGINE == 'truffleruby'
      require 'json/ext/parser'
      require 'json/truffle_ruby/generator'
      JSON.parser = Parser
      JSON.generator = ::JSON::TruffleRuby::Generator
    else
      require 'json/ext/parser'
      require 'json/ext/generator'
      JSON.parser = Parser
      JSON.generator = Generator
    end
  end

  JSON_LOADED = true unless defined?(::JSON::JSON_LOADED)
end
