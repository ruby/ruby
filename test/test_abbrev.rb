require 'test/unit'
require 'abbrev'

class TestAbbrev < Test::Unit::TestCase
  def test_abbrev
    words = %w[summer winter ruby rules]

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
        "w"      => "winter",
        "wi"     => "winter",
        "win"    => "winter",
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
    assert_equal({
        "abc"     => "abc",
        "abc\n"   => "abc\nd",
        "abc\nd"  => "abc\nd",
        "d"       => "de",
        "de"      => "de",
      }, Abbrev.abbrev(["abc", "abc\nd", "de"]))
  end
end
