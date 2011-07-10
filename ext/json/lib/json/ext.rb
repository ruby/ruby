require 'json/common'

module JSON
  # This module holds all the modules/classes that implement JSON's
  # functionality as C extensions.
  module Ext
    begin
      if defined?(RUBY_ENGINE) == 'constant' and RUBY_ENGINE == 'ruby' and RUBY_VERSION =~ /\A1\.9\./
        require 'json/ext/1.9/parser'
        require 'json/ext/1.9/generator'
      elsif !defined?(RUBY_ENGINE) && RUBY_VERSION =~ /\A1\.8\./
        require 'json/ext/1.8/parser'
        require 'json/ext/1.8/generator'
      else
        require 'json/ext/parser'
        require 'json/ext/generator'
      end
    rescue LoadError
      require 'json/ext/parser'
      require 'json/ext/generator'
    end
    $DEBUG and warn "Using Ext extension for JSON."
    JSON.parser = Parser
    JSON.generator = Generator
  end

  JSON_LOADED = true unless defined?(::JSON::JSON_LOADED)
end
