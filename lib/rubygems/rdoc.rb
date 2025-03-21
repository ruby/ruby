# frozen_string_literal: true

require_relative "../rubygems"

begin
  require "rdoc/rubygems_hook"
  module Gem
    ##
    # Returns whether RDoc defines its own install hooks through a RubyGems
    # plugin. This and whatever is guarded by it can be removed once no
    # supported Ruby ships with RDoc older than 6.9.0.

    def self.rdoc_hooks_defined_via_plugin?
      Gem::Version.new(::RDoc::VERSION) >= Gem::Version.new("6.9.0")
    end

    if rdoc_hooks_defined_via_plugin?
      RDoc = ::RDoc::RubyGemsHook
    else
      RDoc = ::RDoc::RubygemsHook

      Gem.done_installing(&Gem::RDoc.method(:generation_hook))
    end
  end
rescue LoadError
end
