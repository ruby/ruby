require 'test/unit'
require 'abbrev'

class TestAbbrev < Test::Unit::TestCase
  def test_abbrev
    words = %w[summer winter win ruby rules]

    assert_equal({
        "rub"    => "ruby",
        "ruby"   => "ruby",
        "rul"    => "rules",
        "rule"   => "rules",
        "rules"  => "rules",
        "s"      => "summer",
        "su"     => "summer",
        "sum"    => "summer",
        "summ"   => "summer",
        "summe"  => "summer",
        "summer" => "summer",
        "win"    => "win",
        "wint"   => "winter",
        "winte"  => "winter",
        "winter" => "winter",
      }, words.abbrev)

    assert_equal({
        "rub"    => "ruby",
        "ruby"   => "ruby",
        "rul"    => "rules",
        "rule"   => "rules",
        "rules"  => "rules",
      }, words.abbrev('ru'))

    assert_equal words.abbrev,       Abbrev.abbrev(words)
    assert_equal words.abbrev('ru'), Abbrev.abbrev(words, 'ru')
  end

  def test_abbrev_lf
    words = ["abc", "abc\nd", "de"]

    assert_equal({
        "abc"     => "abc",
        "abc\n"   => "abc\nd",
        "abc\nd"  => "abc\nd",
        "d"       => "de",
        "de"      => "de",
      }, words.abbrev)

    assert_equal({
        "d"       => "de",
        "de"      => "de",
      }, words.abbrev('d'))
  end
end
