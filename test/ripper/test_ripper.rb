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

  def test_squiggly_heredoc
    assert_equal(Ripper.sexp(<<-eos), Ripper.sexp(<<-eos))
    <<-eot
asdf
    eot
    eos
    <<~eot
      asdf
    eot
    eos
  end

  def test_squiggly_heredoc_with_interpolated_expression
    sexp1 = Ripper.sexp(<<-eos)
<<-eot
a\#{1}z
eot
    eos

    sexp2 = Ripper.sexp(<<-eos)
<<~eot
  a\#{1}z
eot
    eos

    pos = lambda do |s|
      s.fetch(1).fetch(0).fetch(1).fetch(2).fetch(1).fetch(0).fetch(2)
    end
    assert_not_equal pos[sexp1], pos[sexp2]
    pos[sexp1].clear
    pos[sexp2].clear
    assert_equal sexp1, sexp2
  end
end if ripper_test
