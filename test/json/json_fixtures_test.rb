# frozen_string_literal: true
require_relative 'test_helper'

class JSONFixturesTest < Test::Unit::TestCase
  fixtures = File.join(File.dirname(__FILE__), 'fixtures/{fail,pass}*.json')
  passed, failed = Dir[fixtures].partition { |f| f['pass'] }

  passed.each do |f|
    name = File.basename(f).gsub(".", "_")
    source = File.read(f)
    define_method("test_#{name}") do
      assert JSON.parse(source), "Did not pass for fixture '#{File.basename(f)}': #{source.inspect}"
    rescue JSON::ParserError
      raise "#{File.basename(f)} parsing failure"
    end
  end

  failed.each do |f|
    name = File.basename(f).gsub(".", "_")
    source = File.read(f)
    define_method("test_#{name}") do
      assert_raise(JSON::ParserError, JSON::NestingError,
        "Did not fail for fixture '#{name}': #{source.inspect}") do
        JSON.parse(source)
      end
    end
  end
end
