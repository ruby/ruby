#
# $Id$
#
# Copyright (c) 2002 akira yamada <akira@ruby-lang.org>
# You can redistribute it and/or modify it under the same term as Ruby.
#

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'uri'

class TestCommon < RUNIT::TestCase
  def setup
  end

  def teardown
  end

  def test_extract
    # ruby-list:36086
    assert_equal(['http://example.com'], 
		 URI.extract('http://example.com'))
    assert_equal(['http://example.com'], 
		 URI.extract('(http://example.com)'))
    assert_equal(['http://example.com/foo)'], 
		 URI.extract('(http://example.com/foo)'))
    assert_equal(['http://example.jphttp://example.jp'], 
		 URI.extract('http://example.jphttp://example.jp'))
    assert_equal(['http://example.jphttp://example.jp'], 
		 URI.extract('http://example.jphttp://example.jp', ['http']))
    assert_equal(['http://', 'mailto:'].sort, 
		 URI.extract('ftp:// http:// mailto: https://', ['http', 'mailto']).sort)
    # reported by Doug Kearns <djkea2@mugca.its.monash.edu.au>
    assert_equal(['From:', 'mailto:xxx@xxx.xxx.xxx]'].sort, 
		 URI.extract('From: XXX [mailto:xxx@xxx.xxx.xxx]').sort)
  end
end

if $0 == __FILE__
  if ARGV.size == 0
    suite = TestCommon.suite
  else
    suite = RUNIT::TestSuite.new
    ARGV.each do |testmethod|
      suite.add_test(TestGeneric.new(testmethod))
    end
  end
  RUNIT::CUI::TestRunner.run(suite)
end
