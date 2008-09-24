#!/usr/bin/env ruby

require 'test/unit'
require 'json'

class TC_JSONFixtures < Test::Unit::TestCase
  def setup
    fixtures = File.join(File.dirname(__FILE__), 'fixtures/*.json')
    passed, failed = Dir[fixtures].partition { |f| f['pass'] }
    @passed = passed.inject([]) { |a, f| a << [ f, File.read(f) ] }.sort
    @failed = failed.inject([]) { |a, f| a << [ f, File.read(f) ] }.sort
  end

  def test_passing
    for name, source in @passed
      assert JSON.parse(source),
        "Did not pass for fixture '#{name}'"
    end
  end

  def test_failing
    for name, source in @failed
      assert_raise(JSON::ParserError, JSON::NestingError,
        "Did not fail for fixture '#{name}'") do
        JSON.parse(source)
      end
    end
  end
end
