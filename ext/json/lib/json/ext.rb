# frozen_string_literal: true

require 'json/common'

module JSON
  # This module holds all the modules/classes that implement JSON's
  # functionality as C extensions.
  module Ext
    if RUBY_ENGINE == 'truffleruby'
      require 'json/ext/parser'
      require 'json/pure'
      $DEBUG and warn "Using Ext extension for JSON parser and Pure library for JSON generator."
      JSON.parser = Parser
      JSON.generator = JSON::Pure::Generator
    else
      require 'json/ext/parser'
      require 'json/ext/generator'
      $DEBUG and warn "Using Ext extension for JSON."
      JSON.parser = Parser
      JSON.generator = Generator
    end
  end

  JSON_LOADED = true unless defined?(::JSON::JSON_LOADED)
end
