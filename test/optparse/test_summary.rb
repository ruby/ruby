# frozen_string_literal: false
require_relative 'test_optparse'

class TestOptionParserSummaryTest < TestOptionParser
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

  # https://github.com/ruby/optparse/issues/37
  def test_very_long_without_short
    o = OptionParser.new do |opts|
      # This causes TypeError
      opts.on('',   '--long-long-option-param-without-short', "Error desc") { options[:long_long_option_param_without_short] = true }
      opts.on('',   '--long-option-param', "Long desc") { options[:long_option_param_without_short] = true }
      opts.on('-a', '--long-long-option-param-with-short', "Normal description") { options[:long_long_option_param_with_short] = true }

      opts.on('',   '--long-long-option-param-without-short-but-with-desc', 'Description of the long long param') { options[:long_long_option_param_without_short_but_with_desc] = true }
    end

    s = o.summarize

    assert_match(/^\s*--long-long-option-param-without-short$/, s[0])
    assert_match(/^\s*Error desc$/, s[1])
    assert_match(/^\s*--long-option-param\s+Long desc$/, s[2])
    assert_match(/^\s*-a\s+Normal description$/, s[3])
    assert_match(/^\s*--long-long-option-param-with-short$/, s[4])

    assert_match(/^\s*--long-long-option-param-without-short-but-with-desc$/, s[5])
    assert_match(/^\s*Description of the long long param$/, s[6])
  end
end
