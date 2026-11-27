# frozen_string_literal: true

# Reuse RubyGems' vendored PubGrub (Gem::PubGrub). The Bundler gem ships a copy
# under lib/rubygems/vendor, so this resolves even on RubyGems versions that
# predate it.

require "rubygems/vendor/pub_grub/lib/pub_grub"
