# Copyright © 2016 Kimihito Matsui (松井 仁人) and Martin J. Dürst (duerst@it.aoyama.ac.jp)

require "test/unit"

# preliminary tests, using :lithuanian as a guard
# to test new implementation strategy
class TestCaseMappingPreliminary < Test::Unit::TestCase
  # checks, including idempotence and non-modification; not always guaranteed
  def check_upcase_properties(expected, start, *flags)
    assert_equal expected, start.upcase(*flags)
    temp = start.dup
    assert_equal expected, temp.upcase!(*flags)
    assert_equal expected, expected.upcase(*flags)
    temp = expected.dup
    assert_nil   temp.upcase!(*flags)
  end

  def check_downcase_properties(expected, start, *flags)
    assert_equal expected, start.downcase(*flags)
    temp = start.dup
    assert_equal expected, temp.downcase!(*flags)
    assert_equal expected, expected.downcase(*flags)
    temp = expected.dup
    assert_nil   temp.downcase!(*flags)
  end

  def check_capitalize_properties(expected, start, *flags)
    assert_equal expected, start.capitalize(*flags)
    temp = start.dup
    assert_equal expected, temp.capitalize!(*flags)
    assert_equal expected, expected.capitalize(*flags)
    temp = expected.dup
    assert_nil   temp.capitalize!(*flags)
  end

  def check_capitalize_suffixes(lower, upper)
    while upper.length > 1
      lower = lower[1..-1]
      check_capitalize_properties upper[0]+lower, upper, :lithuanian
      upper = upper[1..-1]
    end
  end

  # different properties; careful: roundtrip isn't always guaranteed
  def check_swapcase_properties(expected, start, *flags)
    assert_equal expected, start.swapcase(*flags)
    temp = start
    assert_equal expected, temp.swapcase!(*flags)
    assert_equal start, start.swapcase(*flags).swapcase(*flags)
    assert_equal expected, expected.swapcase(*flags).swapcase(*flags)
  end

  def test_ascii
    check_downcase_properties   'yukihiro matsumoto (matz)', 'Yukihiro MATSUMOTO (MATZ)', :lithuanian
    check_upcase_properties     'YUKIHIRO MATSUMOTO (MATZ)', 'yukihiro matsumoto (matz)', :lithuanian
    check_capitalize_properties 'Yukihiro matsumoto (matz)', 'yukihiro MATSUMOTO (MATZ)', :lithuanian
    check_swapcase_properties   'yUKIHIRO matsumoto (MAtz)', 'Yukihiro MATSUMOTO (maTZ)', :lithuanian
  end

  def test_general
    check_downcase_properties   'résumé dürst ĭñŧėřŋãţĳňőńæłĩżàťïōņ', 'RÉSUMÉ DÜRST ĬÑŦĖŘŊÃŢĲŇŐŃÆŁĨŻÀŤÏŌŅ', :lithuanian
    check_upcase_properties     'RÉSUMÉ DÜRST ĬÑŦĖŘŊÃŢĲŇŐŃÆŁĨŻÀŤÏŌŅ', 'résumé dürst ĭñŧėřŋãţĳňőńæłĩżàťïōņ', :lithuanian
    check_capitalize_suffixes   'résumé dürst ĭñŧėřŋãţĳňőńæłĩżàťïōņ', 'RÉSUMÉ DÜRST ĬÑŦĖŘŊÃŢĲŇŐŃÆŁĨŻÀŤÏŌŅ'
    check_swapcase_properties   'résumé DÜRST ĭñŧėřŊÃŢĲŇŐŃæłĩżàťïōņ', 'RÉSUMÉ dürst ĬÑŦĖŘŋãţĳňőńÆŁĨŻÀŤÏŌŅ', :lithuanian
  end

  def test_various
    check_upcase_properties     'Μ', 'µ', :lithuanian # MICRO SIGN -> Greek Mu
    check_capitalize_properties 'Ss', 'ß', :lithuanian
    check_upcase_properties     'SS', 'ß', :lithuanian
  end

  def test_cherokee
    check_downcase_properties   "\uab70\uab71\uab72\uab73\uab74\uab75\uab76\uab77\uab78\uab79", 'ᎠᎡᎢᎣᎤᎥᎦᎧᎨᎩ', :lithuanian
    check_upcase_properties     'ᎠᎡᎢᎣᎤᎥᎦᎧᎨᎩ', "\uab70\uab71\uab72\uab73\uab74\uab75\uab76\uab77\uab78\uab79", :lithuanian
    check_capitalize_suffixes   "\uab70\uab71\uab72\uab73\uab74\uab75\uab76\uab77\uab78\uab79", 'ᎠᎡᎢᎣᎤᎥᎦᎧᎨᎩ'
    assert_equal                'ᎠᎡᎢᎣᎤᎥᎦᎧᎨᎩ', 'ᎠᎡᎢᎣᎤᎥᎦᎧᎨᎩ'.downcase(:fold)
    assert_equal                'ᎠᎡᎢᎣᎤᎥᎦᎧᎨᎩ', "\uab70\uab71\uab72\uab73\uab74\uab75\uab76\uab77\uab78\uab79".downcase(:fold)
  end

  def test_titlecase
    check_downcase_properties   'ǳ ǆ ǉ ǌ', 'ǲ ǅ ǈ ǋ', :lithuanian
    check_downcase_properties   'ǳ ǆ ǉ ǌ', 'Ǳ Ǆ Ǉ Ǌ', :lithuanian
    check_upcase_properties     'Ǳ Ǆ Ǉ Ǌ', 'ǲ ǅ ǈ ǋ', :lithuanian
    check_upcase_properties     'Ǳ Ǆ Ǉ Ǌ', 'ǳ ǆ ǉ ǌ', :lithuanian
    check_capitalize_properties 'ǲ', 'Ǳ', :lithuanian
    check_capitalize_properties 'ǅ', 'Ǆ', :lithuanian
    check_capitalize_properties 'ǈ', 'Ǉ', :lithuanian
    check_capitalize_properties 'ǋ', 'Ǌ', :lithuanian
    check_capitalize_properties 'ǲ', 'ǳ', :lithuanian
    check_capitalize_properties 'ǅ', 'ǆ', :lithuanian
    check_capitalize_properties 'ǈ', 'ǉ', :lithuanian
    check_capitalize_properties 'ǋ', 'ǌ', :lithuanian
  end

  def test_swapcase
    assert_equal                'dZ', 'ǲ'.swapcase(:lithuanian)
    assert_equal                'dŽ', 'ǅ'.swapcase(:lithuanian)
    assert_equal                'lJ', 'ǈ'.swapcase(:lithuanian)
    assert_equal                'nJ', 'ǋ'.swapcase(:lithuanian)
    assert_equal                'ἀΙ', 'ᾈ'.swapcase(:lithuanian)
    assert_equal                'ἣΙ', 'ᾛ'.swapcase(:lithuanian)
    assert_equal                'ὧΙ', 'ᾯ'.swapcase(:lithuanian)
    assert_equal                'αΙ', 'ᾼ'.swapcase(:lithuanian)
    assert_equal                'ηΙ', 'ῌ'.swapcase(:lithuanian)
    assert_equal                'ωΙ', 'ῼ'.swapcase(:lithuanian)
  end

  def test_ascii_option
    check_downcase_properties   'yukihiro matsumoto (matz)', 'Yukihiro MATSUMOTO (MATZ)', :ascii
    check_upcase_properties     'YUKIHIRO MATSUMOTO (MATZ)', 'yukihiro matsumoto (matz)', :ascii
    check_capitalize_properties 'Yukihiro matsumoto (matz)', 'yukihiro MATSUMOTO (MATZ)', :ascii
    check_swapcase_properties   'yUKIHIRO matsumoto (MAtz)', 'Yukihiro MATSUMOTO (maTZ)', :ascii
    check_downcase_properties   'yukİhİro matsumoto (matz)', 'YUKİHİRO MATSUMOTO (MATZ)', :ascii
    check_downcase_properties   'rÉsumÉ dÜrst ĬÑŦĖŘŊÃŢĲŇŐŃÆŁĨŻÀŤĬŌŅ', 'RÉSUMÉ DÜRST ĬÑŦĖŘŊÃŢĲŇŐŃÆŁĨŻÀŤĬŌŅ', :ascii
    check_swapcase_properties   'rÉsumÉ dÜrst ĬÑŦĖŘŊÃŢĲŇŐŃÆŁĨŻÀŤĬŌŅ', 'RÉSUMÉ DÜRST ĬÑŦĖŘŊÃŢĲŇŐŃÆŁĨŻÀŤĬŌŅ', :ascii
  end

  def test_fold_option
    check_downcase_properties   'ss', 'ß', :fold
    check_downcase_properties   'fifl', 'ﬁﬂ', :fold
    check_downcase_properties   'σ', 'ς', :fold
    check_downcase_properties   'μ', 'µ', :fold # MICRO SIGN -> Greek mu
  end

  def test_turcic
    check_downcase_properties   'yukihiro matsumoto (matz)', 'Yukihiro MATSUMOTO (MATZ)', :turkic
    check_upcase_properties     'YUKİHİRO MATSUMOTO (MATZ)', 'Yukihiro Matsumoto (matz)', :turkic
    check_downcase_properties   "yuki\u0307hi\u0307ro matsumoto (matz)", 'YUKİHİRO MATSUMOTO (MATZ)', :lithuanian
  end

  def test_greek
    check_downcase_properties   'αβγδεζηθικλμνξοπρστυφχψω', 'ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ', :lithuanian
    check_upcase_properties     'ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ', 'αβγδεζηθικλμνξοπρστυφχψω', :lithuanian
  end

  def no_longer_a_test_buffer_allocations
    assert_equal 'TURKISH*ı'*10, ('I'*10).downcase(:turkic, :lithuanian)
    assert_equal 'TURKISH*ı'*100, ('I'*100).downcase(:turkic, :lithuanian)
    assert_equal 'TURKISH*ı'*1_000, ('I'*1_000).downcase(:turkic, :lithuanian)
    assert_equal 'TURKISH*ı'*10_000, ('I'*10_000).downcase(:turkic, :lithuanian)
    assert_equal 'TURKISH*ı'*100_000, ('I'*100_000).downcase(:turkic, :lithuanian)
    assert_equal 'TURKISH*ı'*1_000_000, ('I'*1_000_000).downcase(:turkic, :lithuanian)
  end
end
