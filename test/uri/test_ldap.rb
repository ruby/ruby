#
# $Id$
#
# Copyright (c) 2001 Takaaki Tateishi <ttate@jaist.ac.jp> and 
# akira yamada <akira@ruby-lang.org>.
# You can redistribute it and/or modify it under the same term as Ruby.
#

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'uri/ldap'
module URI
  class Generic
    def to_ary
      component_ary
    end
  end
end

class TestLDAP < RUNIT::TestCase
  def setup
  end

  def teardown
  end

  def test_parse
    url = 'ldap://ldap.jaist.ac.jp/o=JAIST,c=JP?sn?base?(sn=ttate*)'
    u = URI.parse(url)
    assert_kind_of(URI::LDAP, u)
    assert_equal(url, u.to_s)
    assert_equal('o=JAIST,c=JP', u.dn)
    assert_equal('sn', u.attributes)
    assert_equal('base', u.scope)
    assert_equal('(sn=ttate*)', u.filter)
    assert_equal(nil, u.extensions)

    u.scope = URI::LDAP::SCOPE_SUB
    u.attributes = 'sn,cn,mail'
    assert_equal('ldap://ldap.jaist.ac.jp/o=JAIST,c=JP?sn,cn,mail?sub?(sn=ttate*)', u.to_s)
    assert_equal('o=JAIST,c=JP', u.dn)
    assert_equal('sn,cn,mail', u.attributes)
    assert_equal('sub', u.scope)
    assert_equal('(sn=ttate*)', u.filter)
    assert_equal(nil, u.extensions)

    # from RFC2255, section 6.
    urls = {
      'ldap:///o=University%20of%20Michigan,c=US' =>
      ['ldap', nil, URI::LDAP::DEFAULT_PORT, 
	'o=University%20of%20Michigan,c=US', 
	nil, nil, nil, nil],

      'ldap://ldap.itd.umich.edu/o=University%20of%20Michigan,c=US' =>
      ['ldap', 'ldap.itd.umich.edu', URI::LDAP::DEFAULT_PORT, 
	'o=University%20of%20Michigan,c=US', 
	nil, nil, nil, nil],

      'ldap://ldap.itd.umich.edu/o=University%20of%20Michigan,c=US?postalAddress' =>
      ['ldap', 'ldap.itd.umich.edu', URI::LDAP::DEFAULT_PORT, 
	'o=University%20of%20Michigan,c=US',
	'postalAddress', nil, nil, nil],

      'ldap://host.com:6666/o=University%20of%20Michigan,c=US??sub?(cn=Babs%20Jensen)' =>
      ['ldap', 'host.com', 6666, 
	'o=University%20of%20Michigan,c=US',
	nil, 'sub', '(cn=Babs%20Jensen)', nil],

      'ldap://ldap.itd.umich.edu/c=GB?objectClass?one' =>
      ['ldap', 'ldap.itd.umich.edu', URI::LDAP::DEFAULT_PORT, 
	'c=GB', 
	'objectClass', 'one', nil, nil],

      'ldap://ldap.question.com/o=Question%3f,c=US?mail' =>
      ['ldap', 'ldap.question.com', URI::LDAP::DEFAULT_PORT, 
	'o=Question%3f,c=US',
	'mail', nil, nil, nil],

      'ldap://ldap.netscape.com/o=Babsco,c=US??(int=%5c00%5c00%5c00%5c04)' =>
      ['ldap', 'ldap.netscape.com', URI::LDAP::DEFAULT_PORT, 
	'o=Babsco,c=US',
	nil, '(int=%5c00%5c00%5c00%5c04)', nil, nil],

      'ldap:///??sub??bindname=cn=Manager%2co=Foo' =>
      ['ldap', nil, URI::LDAP::DEFAULT_PORT, 
	'',
	nil, 'sub', nil, 'bindname=cn=Manager%2co=Foo'],

      'ldap:///??sub??!bindname=cn=Manager%2co=Foo' =>
      ['ldap', nil, URI::LDAP::DEFAULT_PORT, 
	'',
	nil, 'sub', nil, '!bindname=cn=Manager%2co=Foo'],
    }.each do |url, ary|
      u = URI.parse(url)
      assert_equal(ary, u.to_ary)
    end
  end

  def test_select
    u = URI.parse('ldap:///??sub??!bindname=cn=Manager%2co=Foo')
    assert_equal(u.to_ary, u.select(*u.component))
    assert_exception(ArgumentError) do
      u.select(:scheme, :host, :not_exist, :port)
    end
  end
end

if $0 == __FILE__
  if ARGV.size == 0
    suite = TestLDAP.suite
  else
    suite = RUNIT::TestSuite.new
    ARGV.each do |testmethod|
      suite.add_test(TestLDAP.new(testmethod))
    end
  end
  RUNIT::CUI::TestRunner.run(suite)
end
