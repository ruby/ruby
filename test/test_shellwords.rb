# -*- coding: utf-8 -*-
require 'test/unit'
require 'shellwords'

class TestShellwords < Test::Unit::TestCase

  include Shellwords

  def test_shellwords
    cmd1 = "ruby -i'.bak' -pe \"sub /foo/, '\\\\&bar'\" foobar\\ me.txt\n"
    assert_equal(['ruby', '-i.bak', '-pe', "sub /foo/, '\\&bar'", "foobar me.txt"],
                 shellwords(cmd1))

    # shellwords does not interpret meta-characters
    cmd2 = "ruby my_prog.rb | less"
    assert_equal(['ruby', 'my_prog.rb', '|', 'less'],
                 shellwords(cmd2))
  end

  def test_unmatched_double_quote
    bad_cmd = 'one two "three'
    assert_raise ArgumentError do
      shellwords(bad_cmd)
    end
  end

  def test_unmatched_single_quote
    bad_cmd = "one two 'three"
    assert_raise ArgumentError do
      shellwords(bad_cmd)
    end
  end

  def test_unmatched_quotes
    bad_cmd = "one '"'"''""'""
    assert_raise ArgumentError do
      shellwords(bad_cmd)
    end
  end

  def test_backslashes
    cmdline, expected = [
      %q{/a//b///c////d/////e/ "/a//b///c////d/////e/ "'/a//b///c////d/////e/ '/a//b///c////d/////e/ },
      %q{a/b/c//d//e a/b/c//d//e /a//b///c////d/////e/ a/b/c//d//e }
    ].map { |str| str.tr("/", "\\\\") }

    assert_equal [expected], shellwords(cmdline)
  end

  def test_stringification
    three = shellescape(3)
    assert_equal '3', three
    assert_not_predicate three, :frozen?

    empty = shellescape('')
    assert_equal "''", empty
    assert_not_predicate empty, :frozen?

    joined = ['ps', '-p', $$].shelljoin
    assert_equal "ps -p #{$$}", joined
    assert_not_predicate joined, :frozen?
  end

  def test_multibyte_characters
    # This is not a spec.  It describes the current behavior which may
    # be changed in future.  There would be no multibyte character
    # used as shell meta-character that needs to be escaped.
    assert_equal "\\あ\\い", "あい".shellescape
  end
end
