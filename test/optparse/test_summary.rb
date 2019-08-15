# frozen_string_literal: false
require_relative 'test_optparse'

class TestOptionParser::SummaryTest < TestOptionParser
  def test_short_clash
    r = nil
    o = OptionParser.new do |opts|
      opts.on("-f", "--first-option", "description 1", "description 2"){r = "first-option"}
      opts.on("-t", "--test-option"){r = "test-option"}
      opts.on("-t", "--another-test-option"){r = "another-test-option"}
      opts.separator "this is\nseparator"
      opts.on("-l", "--last-option"){r = "last-option"}
    end
    s = o.summarize
    o.parse("-t")
    assert_match(/--#{r}/, s.grep(/^\s*-t,/)[0])
    assert_match(/first-option/, s[0])
    assert_match(/description 1/, s[0])
    assert_match(/description 2/, s[1])
    assert_match(/last-option/, s[-1])
  end

  def test_banner
    o = OptionParser.new("foo bar")
    assert_equal("foo bar", o.banner)
  end

  def test_banner_from_progname
    o = OptionParser.new
    o.program_name = "foobar"
    assert_equal("Usage: foobar [options]\n", o.help)
  end

  def test_summary
    o = OptionParser.new("foo\nbar")
    assert_equal("foo\nbar\n", o.to_s)
    assert_equal(["foo\n", "bar"], o.to_a)
  end

  def test_summary_containing_space
    # test for r35467. OptionParser#to_a shouldn't split str by spaces.
    bug6348 = '[ruby-dev:45568]'
    o = OptionParser.new("foo bar")
    assert_equal("foo bar\n", o.to_s, bug6348)
    assert_equal(["foo bar"], o.to_a, bug6348)
  end

  def test_ver
    o = OptionParser.new("foo bar")
    o.program_name = "foo"
    assert_warning('') {assert_nil(o.version)}
    assert_warning('') {assert_nil(o.release)}
    o.version = [0, 1]
    assert_equal "foo 0.1", o.ver
    o.release = "rel"
    assert_equal "foo 0.1 (rel)", o.ver
  end
end
