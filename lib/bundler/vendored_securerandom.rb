# frozen_string_literal: true

# Reuse RubyGems' vendored SecureRandom (Gem::SecureRandom). The Bundler gem
# ships a copy under lib/rubygems/vendor, so this resolves even on RubyGems
# versions that predate it. Fall back to the stdlib only when no vendored copy
# is available at all.

unless defined?(Gem::SecureRandom)
  begin
    require "rubygems/vendor/securerandom/lib/securerandom"
  rescue LoadError
    require "securerandom"
    Gem::SecureRandom = SecureRandom
  end
end
