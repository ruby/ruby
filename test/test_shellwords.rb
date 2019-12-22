# -*- coding: utf-8 -*-
# frozen_string_literal: false
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

    [
      [
        %q{/a//b///c////d/////e/ "/a//b///c////d/////e/ "'/a//b///c////d/////e/ '/a//b///c////d/////e/ },
        'a/b/c//d//e /a/b//c//d///e/ /a//b///c////d/////e/ a/b/c//d//e '
      ],
      [
        %q{printf %s /"/$/`///"/r/n},
        'printf', '%s', '"$`/"rn'
      ],
      [
        %q{printf %s "/"/$/`///"/r/n"},
        'printf', '%s', '"$`/"/r/n'
      ]
    ].map { |strs|
      cmdline, *expected = strs.map { |str| str.tr("/", "\\\\") }
      assert_equal expected, shellwords(cmdline)
    }
  end

  def test_stringification
    three = shellescape(3)
    assert_equal '3', three

    joined = ['ps', '-p', $$].shelljoin
    assert_equal "ps -p #{$$}", joined
  end

  def test_shellescape
    assert_equal "''", shellescape('')
    assert_equal "\\^AZaz09_\\\\-.,:/@'\n'+\\'\\\"", shellescape("^AZaz09_\\-.,:\/@\n+'\"")
  end

  def test_whitespace
    empty = ''
    space = " "
    newline = "\n"
    tab = "\t"

    tokens = [
      empty,
      space,
      space * 2,
      newline,
      newline * 2,
      tab,
      tab * 2,
      empty,
      space + newline + tab,
      empty
    ]

    tokens.each { |token|
      assert_equal [token], shellescape(token).shellsplit
    }


    assert_equal tokens, shelljoin(tokens).shellsplit
  end

  def test_frozenness
    [
      shellescape(String.new),
      shellescape(String.new('foo')),
      shellescape(''.freeze),
      shellescape("\n".freeze),
      shellescape('foo'.freeze),
      shelljoin(['ps'.freeze, 'ax'.freeze]),
    ].each { |object|
      assert_not_predicate object, :frozen?
    }

    [
      shellsplit('ps'),
      shellsplit('ps ax'),
    ].each { |array|
      array.each { |arg|
        assert_not_predicate arg, :frozen?, array.inspect
      }
    }
  end

  def test_multibyte_characters
    # This is not a spec.  It describes the current behavior which may
    # be changed in future.  There would be no multibyte character
    # used as shell meta-character that needs to be escaped.
    assert_equal "\\あ\\い", "あい".shellescape
  end
end
