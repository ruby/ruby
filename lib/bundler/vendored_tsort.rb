# frozen_string_literal: true

# The defined? guard avoids reopening Gem::TSort when an old RubyGems has
# already loaded its own copy, e.g. through rubygems/request_set from
# Gem.activate_bin_path in binstubs.
#
unless defined?(Gem::TSort)
  begin
    require "rubygems/vendored_tsort"
  rescue LoadError
    begin
      # RubyGems 3.4 and 3.5 ship the same file under its pre-3.6 name.
      # Requiring the real tsort here instead would activate the tsort
      # default gem, and `bundler/setup` must not activate any gems.
      require "rubygems/tsort"
    rescue LoadError
      require "tsort"
      Gem::TSort = TSort
    end
  end
end
