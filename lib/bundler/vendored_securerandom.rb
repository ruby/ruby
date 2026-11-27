# frozen_string_literal: true

# Reuse RubyGems' vendored SecureRandom (Gem::SecureRandom). The Bundler gem
# ships a copy under lib/rubygems/vendor, so this resolves even on RubyGems
# versions that predate it. Fall back to the stdlib only when no vendored copy
# is available at all. RubyGems' own file is required by path for the reason
# given in vendored_uri.rb.

unless defined?(Gem::SecureRandom)
  rubygems_securerandom = File.join(Gem::RUBYGEMS_DIR, "rubygems/vendor/securerandom/lib/securerandom.rb")

  begin
    require File.exist?(rubygems_securerandom) ? rubygems_securerandom : "rubygems/vendor/securerandom/lib/securerandom"
  rescue LoadError
    require "securerandom"
    Gem::SecureRandom = SecureRandom
  end
end
