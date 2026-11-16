# frozen_string_literal: true

# Reuse RubyGems' vendored URI (Gem::URI). The Bundler gem ships a copy under
# lib/rubygems/vendor, so this resolves even on RubyGems versions that predate
# it. Fall back to the stdlib only when no vendored copy is available at all.
#
# RubyGems requires its own copy with require_relative, so require that same
# file when it exists. A require by feature name finds the copy shipped in this
# gem first, and older RubyGems versions, whose copy has no double load guard,
# would then load the library a second time.

unless defined?(Gem::URI)
  rubygems_uri = File.join(Gem::RUBYGEMS_DIR, "rubygems/vendor/uri/lib/uri.rb")

  begin
    require File.exist?(rubygems_uri) ? rubygems_uri : "rubygems/vendor/uri/lib/uri"
  rescue LoadError
    require "uri"
    Gem::URI = URI

    module Gem
      def URI(uri) # rubocop:disable Naming/MethodName
        Kernel.URI(uri)
      end
      module_function :URI
    end
  end
end
