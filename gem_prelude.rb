if defined?(Gem)
  require 'rubygems.rb'
  begin
    gem 'did_you_mean'
    require 'did_you_mean'
  rescue Gem::LoadError, LoadError
  end if defined?(DidYouMean)
end
