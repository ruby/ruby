begin
  require 'rubygems'
rescue LoadError
  warn "`RubyGems' were not loaded."
end if defined?(Gem)

begin
  require 'error_squiggle'
rescue LoadError
  warn "`error_squiggle' was not loaded."
end if defined?(ErrorSquiggle)

begin
  require 'did_you_mean'
rescue LoadError
  warn "`did_you_mean' was not loaded."
end if defined?(DidYouMean)
