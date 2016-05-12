# frozen_string_literal: false
if ENV['SIMPLECOV_COVERAGE'].to_i == 1
  require 'simplecov'
  SimpleCov.start do
    add_filter "/tests/"
  end
end
require 'json/common'

module JSON
  # This module holds all the modules/classes that implement JSON's
  # functionality as C extensions.
  module Ext
    require 'json/ext/parser'
    require 'json/ext/generator'
    $DEBUG and warn "Using Ext extension for JSON."
    JSON.parser = Parser
    JSON.generator = Generator
  end

  JSON_LOADED = true unless defined?(::JSON::JSON_LOADED)
end
