# frozen_string_literal: false
begin
  require 'ripper'
  require 'test/unit'
  ripper_test = true
  module TestRipper; end
rescue LoadError
end

class TestRipper::Ripper < Test::Unit::TestCase

  def setup
    @ripper = Ripper.new '1 + 1'
  end

  def test_column
    assert_nil @ripper.column
  end

  def test_encoding
    assert_equal Encoding::UTF_8, @ripper.encoding
    ripper = Ripper.new('# coding: iso-8859-15')
    ripper.parse
    assert_equal Encoding::ISO_8859_15, ripper.encoding
    ripper = Ripper.new('# -*- coding: iso-8859-15 -*-')
    ripper.parse
    assert_equal Encoding::ISO_8859_15, ripper.encoding
  end

  def test_end_seen_eh
    @ripper.parse
    assert_not_predicate @ripper, :end_seen?
    ripper = Ripper.new('__END__')
    ripper.parse
    assert_predicate ripper, :end_seen?
  end

  def test_filename
    assert_equal '(ripper)', @ripper.filename
    filename = "ripper"
    ripper = Ripper.new("", filename)
    filename.clear
    assert_equal "ripper", ripper.filename
  end

  def test_lineno
    assert_nil @ripper.lineno
  end

  def test_parse
    assert_nil @ripper.parse
  end

  def test_yydebug
    assert_not_predicate @ripper, :yydebug
  end

  def test_yydebug_equals
    @ripper.yydebug = true

    assert_predicate @ripper, :yydebug
  end

  def test_regexp_with_option
    bug11932 = '[ruby-core:72638] [Bug #11932]'
    src = '/[\xC0-\xF0]/u'.force_encoding(Encoding::UTF_8)
    ripper = Ripper.new(src)
    ripper.parse
    assert_predicate(ripper, :error?)
    src = '/[\xC0-\xF0]/n'.force_encoding(Encoding::UTF_8)
    ripper = Ripper.new(src)
    ripper.parse
    assert_not_predicate(ripper, :error?, bug11932)
  end
end if ripper_test
