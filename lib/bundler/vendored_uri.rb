# frozen_string_literal: true

# Reuse RubyGems' vendored URI (Gem::URI). The Bundler gem ships a copy under
# lib/rubygems/vendor, so this resolves even on RubyGems versions that predate
# it. Fall back to the stdlib only when no vendored copy is available at all.

unless defined?(Gem::URI)
  begin
    require "rubygems/vendor/uri/lib/uri"
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
