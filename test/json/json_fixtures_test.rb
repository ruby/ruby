# frozen_string_literal: true
require_relative 'test_helper'

class JSONFixturesTest < Test::Unit::TestCase
  def setup
    fixtures = File.join(File.dirname(__FILE__), 'fixtures/{fail,pass}*.json')
    passed, failed = Dir[fixtures].partition { |f| f['pass'] }
    @passed = passed.inject([]) { |a, f| a << [ f, File.read(f) ] }.sort
    @failed = failed.inject([]) { |a, f| a << [ f, File.read(f) ] }.sort
  end

  def test_passing
    verbose_bak, $VERBOSE = $VERBOSE, nil
    for name, source in @passed
      begin
        assert JSON.parse(source),
          "Did not pass for fixture '#{name}': #{source.inspect}"
      rescue => e
        warn "\nCaught #{e.class}(#{e}) for fixture '#{name}': #{source.inspect}\n#{e.backtrace * "\n"}"
        raise e
      end
    end
  ensure
    $VERBOSE = verbose_bak
  end

  def test_failing
    for name, source in @failed
      assert_raise(JSON::ParserError, JSON::NestingError,
        "Did not fail for fixture '#{name}': #{source.inspect}") do
        JSON.parse(source)
      end
    end
  end

  def test_sanity
    assert(@passed.size > 5)
    assert(@failed.size > 20)
  end
end
