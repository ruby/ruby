#
# $Id$
#
# Copyright (c) 2001 akira yamada <akira@ruby-lang.org>
# You can redistribute it and/or modify it under the same term as Ruby.
#

require 'runit/testcase'
require 'runit/testsuite'
require 'runit/cui/testrunner'

require 'uri/ftp'
module URI
  class Generic
    def to_ary
      component_ary
    end
  end
end

class TestFTP < RUNIT::TestCase
  def setup
  end

  def test_parse
    url = URI.parse('ftp://user:pass@host.com/abc/def')
    assert_kind_of(URI::FTP, url)

    exp = [
      'ftp',
      'user:pass', 'host.com', URI::FTP.default_port, 
      '/abc/def', nil,
    ]
    ary = url.to_ary
    assert_equal(exp, ary)

    assert_equal('user', url.user)
    assert_equal('pass', url.password)
  end

  def test_select
    assert_equal(['ftp', 'a.b.c', 21], URI.parse('ftp://a.b.c/').select(:scheme, :host, :port))
    u = URI.parse('ftp://a.b.c/')
    assert_equal(u.to_ary, u.select(*u.component))
    assert_exception(ArgumentError) do
      u.select(:scheme, :host, :not_exist, :port)
    end
  end
end

if $0 == __FILE__
  if ARGV.size == 0
    suite = TestFTP.suite
  else
    suite = RUNIT::TestSuite.new
    ARGV.each do |testmethod|
      suite.add_test(TestFTP.new(testmethod))
    end
  end
  RUNIT::CUI::TestRunner.run(suite)
end
