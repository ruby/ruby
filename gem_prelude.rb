begin
  require 'rubygems.rb'
rescue LoadError
end if defined?(Gem)

begin
  require 'did_you_mean'
rescue LoadError
  warn "`did_you_mean' was not loaded."
end if defined?(DidYouMean)
