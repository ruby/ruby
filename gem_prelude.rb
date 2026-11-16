begin
  # rubygems.rb requires ENV["BUNDLER_SETUP"] while it loads, which is before
  # the libraries given with -r on the command line. That must not happen
  # outside the main box: Bundler evaluates gemspecs through TOPLEVEL_BINDING,
  # which always belongs to the main box, so it would run Bundler code there
  # before RubyGems finishes loading.
  if defined?(Ruby::Box) && Ruby::Box.enabled? && !Ruby::Box.current.main?
    bundler_setup = ENV.delete("BUNDLER_SETUP")
  end
  require 'rubygems'
rescue LoadError => e
  raise unless e.path == 'rubygems'

  warn "`RubyGems' were not loaded."
else
  require 'bundled_gems'
ensure
  ENV["BUNDLER_SETUP"] = bundler_setup if bundler_setup
end if defined?(Gem)
