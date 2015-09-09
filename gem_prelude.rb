if defined?(Gem)
  require 'rubygems.rb'
  begin
    require 'did_you_mean'
  rescue LoadError
  end if defined?(DidYouMean)
end
