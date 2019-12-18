require 'rubygems.rb' if defined?(Gem)

begin
  require 'did_you_mean'
rescue LoadError
end if defined?(DidYouMean)
