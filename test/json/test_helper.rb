case ENV['JSON']
when 'pure'
  $:.unshift 'lib'
  require 'json/pure'
when 'ext'
  $:.unshift 'ext', 'lib'
  require 'json/ext'
else
  $:.unshift 'ext', 'lib'
  require 'json'
end

require 'test/unit'
begin
  require 'byebug'
rescue LoadError
end
if ENV['START_SIMPLECOV'].to_i == 1
  require 'simplecov'
  SimpleCov.start
end
