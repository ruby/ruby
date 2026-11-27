# frozen_string_literal: true

# Reuse RubyGems' vendored URI (Gem::URI). The Bundler gem ships a copy under
# lib/rubygems/vendor without its entry file, which Bundler 2.5.6 to 4.0.x
# require by name on RubyGems older than 3.5.6 (see
# lib/rubygems/yaml_serializer/core.rb), so this loads the files that entry file
# loads on RubyGems versions that predate it. Fall back to the stdlib only when
# no vendored copy is available at all.
#
# RubyGems requires its own copy with require_relative, so require that same
# file when it exists. Older RubyGems versions, whose copy has no double load
# guard, would otherwise load the library a second time.

unless defined?(Gem::URI)
  rubygems_uri = File.join(Gem::RUBYGEMS_DIR, "rubygems/vendor/uri/lib/uri.rb")

  begin
    if File.exist?(rubygems_uri)
      require rubygems_uri
    else
      %w[version common generic file ftp http https ldap ldaps mailto ws wss].each do |file|
        require_relative "../rubygems/vendor/uri/lib/uri/#{file}"
      end
    end
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
