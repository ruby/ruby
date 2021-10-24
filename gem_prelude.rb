begin
  require 'rubygems'
rescue LoadError => e
  raise unless e.path == 'rubygems'

  warn "`RubyGems' were not loaded."
end if defined?(Gem)

begin
  require 'error_highlight'
rescue LoadError
  warn "`error_highlight' was not loaded."
end if defined?(ErrorHighlight)

begin
  require 'did_you_mean'
rescue LoadError
  warn "`did_you_mean' was not loaded."
end if defined?(DidYouMean)
