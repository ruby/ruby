# frozen_string_literal: true

require_relative "../rubygems"

begin
  require "rdoc/rubygems_hook"
  module Gem
    RDoc = ::RDoc::RubygemsHook

    ##
    # Returns whether RDoc defines its own install hooks through a RubyGems
    # plugin. This and whatever is guarded by it can be removed once no
    # supported Ruby ships with RDoc older than 6.9.0.

    def self.rdoc_hooks_defined_via_plugin?
      Gem::Version.new(::RDoc::VERSION) >= Gem::Version.new("6.9.0")
    end
  end

  Gem.done_installing(&Gem::RDoc.method(:generation_hook)) unless Gem.rdoc_hooks_defined_via_plugin?
rescue LoadError
end
