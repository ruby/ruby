case ENV['JSON']
when 'pure'
  $:.unshift File.join(__dir__, '../../lib')
  require 'json/pure'
when 'ext'
  $:.unshift File.join(__dir__, '../../ext'), File.join(__dir__, '../../lib')
  require 'json/ext'
else
  $:.unshift File.join(__dir__, '../../ext'), File.join(__dir__, '../../lib')
  require 'json'
end

require 'test/unit'
begin
  require 'byebug'
rescue LoadError
end

unless defined?(Test::Unit::CoreAssertions)
  require "core_assertions"
  Test::Unit::TestCase.include Test::Unit::CoreAssertions
end
