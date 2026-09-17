begin
  # rubygems.rb requires ENV["BUNDLER_SETUP"] at its end so that bundler/setup
  # runs before error_highlight, did_you_mean and syntax_suggest are loaded.
  # That is unnecessary once they are autoloaded ([Feature #21951]), and it
  # must not happen outside the main box: Bundler evaluates gemspecs through
  # TOPLEVEL_BINDING, which always belongs to the main box, so it would run
  # Bundler code there before RubyGems finishes loading. Either way Bundler is
  # set up by RUBYOPT=-rbundler/setup after the boot sequence.
  if %i[ErrorHighlight DidYouMean SyntaxSuggest].any? {|c| Object.autoload?(c) } ||
     (defined?(Ruby::Box) && Ruby::Box.enabled? && !Ruby::Box.current.main?)
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
