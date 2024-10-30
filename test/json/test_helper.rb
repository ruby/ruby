case ENV['JSON']
when 'pure'
  $LOAD_PATH.unshift(File.expand_path('../../../lib', __FILE__))
  $stderr.puts("Testing JSON::Pure")
  require 'json/pure'
when 'ext'
  $stderr.puts("Testing JSON::Ext")
  $LOAD_PATH.unshift(File.expand_path('../../../ext', __FILE__), File.expand_path('../../../lib', __FILE__))
  require 'json/ext'
else
  $LOAD_PATH.unshift(File.expand_path('../../../ext', __FILE__), File.expand_path('../../../lib', __FILE__))
  $stderr.puts("Testing JSON")
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
