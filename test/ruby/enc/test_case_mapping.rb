# Copyright © 2016 Kimihito Matsui (松井 仁人) and Martin J. Dürst (duerst@it.aoyama.ac.jp)

require "test/unit"

# preliminary tests, using  as a guard
# to test new implementation strategy
class TestCaseMappingPreliminary < Test::Unit::TestCase
  # checks, including idempotence and non-modification; not always guaranteed
  def check_upcase_properties(expected, start, *flags)
    assert_equal expected, start.upcase(*flags)
    temp = start.dup
    assert_equal expected, temp.upcase!(*flags) unless expected==temp
    assert_equal nil, temp.upcase!(*flags) if expected==temp
    assert_equal expected, expected.upcase(*flags)
    temp = expected.dup
    assert_nil   temp.upcase!(*flags)
  end

  def check_downcase_properties(expected, start, *flags)
    assert_equal expected, start.downcase(*flags)
    temp = start.dup
    assert_equal expected, temp.downcase!(*flags) unless expected==temp
    assert_equal nil, temp.downcase!(*flags) if expected==temp
    assert_equal expected, expected.downcase(*flags)
    temp = expected.dup
    assert_nil   temp.downcase!(*flags)
  end

  def check_capitalize_properties(expected, start, *flags)
    assert_equal expected, start.capitalize(*flags)
    temp = start.dup
    assert_equal expected, temp.capitalize!(*flags) unless expected==temp
    assert_equal nil, temp.capitalize!(*flags) if expected==temp
    assert_equal expected, expected.capitalize(*flags)
    temp = expected.dup
    assert_nil   temp.capitalize!(*flags)
  end

  def check_capitalize_suffixes(lower, upper)
    while upper.length > 1
      lower = lower[1..-1]
      check_capitalize_properties upper[0]+lower, upper
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
    check_downcase_properties   'yukihiro matsumoto (matz)', 'Yukihiro MATSUMOTO (MATZ)'
    check_upcase_properties     'YUKIHIRO MATSUMOTO (MATZ)', 'yukihiro matsumoto (matz)'
    check_capitalize_properties 'Yukihiro matsumoto (matz)', 'yukihiro MATSUMOTO (MATZ)'
    check_swapcase_properties   'yUKIHIRO matsumoto (MAtz)', 'Yukihiro MATSUMOTO (maTZ)'
  end

  def test_invalid
    assert_raise(ArgumentError, "Should not be possible to upcase invalid string.") { "\xEB".force_encoding('UTF-8').upcase }
    assert_raise(ArgumentError, "Should not be possible to downcase invalid string.") { "\xEB".force_encoding('UTF-8').downcase }
    assert_raise(ArgumentError, "Should not be possible to capitalize invalid string.") { "\xEB".force_encoding('UTF-8').capitalize }
    assert_raise(ArgumentError, "Should not be possible to swapcase invalid string.") { "\xEB".force_encoding('UTF-8').swapcase }
  end

  def test_general
    check_downcase_properties   'résumé dürst ĭñŧėřŋãţĳňőńæłĩżàťïōņ', 'RÉSUMÉ DÜRST ĬÑŦĖŘŊÃŢĲŇŐŃÆŁĨŻÀŤÏŌŅ'
    check_upcase_properties     'RÉSUMÉ DÜRST ĬÑŦĖŘŊÃŢĲŇŐŃÆŁĨŻÀŤÏŌŅ', 'résumé dürst ĭñŧėřŋãţĳňőńæłĩżàťïōņ'
    check_capitalize_suffixes   'résumé dürst ĭñŧėřŋãţĳňőńæłĩżàťïōņ', 'RÉSUMÉ DÜRST ĬÑŦĖŘŊÃŢĲŇŐŃÆŁĨŻÀŤÏŌŅ'
    check_swapcase_properties   'résumé DÜRST ĭñŧėřŊÃŢĲŇŐŃæłĩżàťïōņ', 'RÉSUMÉ dürst ĬÑŦĖŘŋãţĳňőńÆŁĨŻÀŤÏŌŅ'
  end

  def test_one_way_upcase
    check_upcase_properties     'ΜΜΜΜΜ', 'µµµµµ' # MICRO SIGN -> Greek Mu
    check_downcase_properties   'µµµµµ', 'µµµµµ' # MICRO SIGN -> Greek Mu
    check_capitalize_properties 'Μµµµµ', 'µµµµµ' # MICRO SIGN -> Greek Mu
    check_capitalize_properties 'Μµµµµ', 'µµµµµ', :turkic # MICRO SIGN -> Greek Mu
    check_capitalize_properties 'H̱ẖẖẖẖ', 'ẖẖẖẖẖ'
    check_capitalize_properties 'Βϐϐϐϐ', 'ϐϐϐϐϐ'
    check_capitalize_properties 'Θϑϑϑϑ', 'ϑϑϑϑϑ'
    check_capitalize_properties 'Φϕ', 'ϕϕ'
    check_capitalize_properties 'Πϖ', 'ϖϖ'
    check_capitalize_properties 'Κϰ', 'ϰϰ'
    check_capitalize_properties 'Ρϱϱ', 'ϱϱϱ'
    check_capitalize_properties 'Εϵ', 'ϵϵ'
    check_capitalize_properties 'Ιͅͅͅͅ', 'ͅͅͅͅͅ'
    check_capitalize_properties 'Sſſſſ', 'ſſſſſ'
  end

  def test_various
    check_upcase_properties     'Μ', 'µ' # MICRO SIGN -> Greek Mu
    check_downcase_properties   'µµµµµ', 'µµµµµ' # MICRO SIGN
    check_capitalize_properties 'Ss', 'ß'
    check_upcase_properties     'SS', 'ß'
  end

  def test_cherokee
    check_downcase_properties   "\uab70\uab71\uab72\uab73\uab74\uab75\uab76\uab77\uab78\uab79", 'ᎠᎡᎢᎣᎤᎥᎦᎧᎨᎩ'
    check_upcase_properties     'ᎠᎡᎢᎣᎤᎥᎦᎧᎨᎩ', "\uab70\uab71\uab72\uab73\uab74\uab75\uab76\uab77\uab78\uab79"
    check_capitalize_suffixes   "\uab70\uab71\uab72\uab73\uab74\uab75\uab76\uab77\uab78\uab79", 'ᎠᎡᎢᎣᎤᎥᎦᎧᎨᎩ'
    assert_equal                'ᎠᎡᎢᎣᎤᎥᎦᎧᎨᎩ', 'ᎠᎡᎢᎣᎤᎥᎦᎧᎨᎩ'.downcase(:fold)
    assert_equal                'ᎠᎡᎢᎣᎤᎥᎦᎧᎨᎩ', "\uab70\uab71\uab72\uab73\uab74\uab75\uab76\uab77\uab78\uab79".downcase(:fold)
  end

  def test_titlecase
    check_downcase_properties   'ǳ ǆ ǉ ǌ', 'ǲ ǅ ǈ ǋ'
    check_downcase_properties   'ǳ ǆ ǉ ǌ', 'Ǳ Ǆ Ǉ Ǌ'
    check_upcase_properties     'Ǳ Ǆ Ǉ Ǌ', 'ǲ ǅ ǈ ǋ'
    check_upcase_properties     'Ǳ Ǆ Ǉ Ǌ', 'ǳ ǆ ǉ ǌ'
    check_capitalize_properties 'ǲ', 'Ǳ'
    check_capitalize_properties 'ǅ', 'Ǆ'
    check_capitalize_properties 'ǈ', 'Ǉ'
    check_capitalize_properties 'ǋ', 'Ǌ'
    check_capitalize_properties 'ǲ', 'ǳ'
    check_capitalize_properties 'ǅ', 'ǆ'
    check_capitalize_properties 'ǈ', 'ǉ'
    check_capitalize_properties 'ǋ', 'ǌ'
  end

  def test_swapcase
    assert_equal                'dZ', 'ǲ'.swapcase
    assert_equal                'dŽ', 'ǅ'.swapcase
    assert_equal                'lJ', 'ǈ'.swapcase
    assert_equal                'nJ', 'ǋ'.swapcase
    assert_equal                'ἀΙ', 'ᾈ'.swapcase
    assert_equal                'ἣΙ', 'ᾛ'.swapcase
    assert_equal                'ὧΙ', 'ᾯ'.swapcase
    assert_equal                'αΙ', 'ᾼ'.swapcase
    assert_equal                'ηΙ', 'ῌ'.swapcase
    assert_equal                'ωΙ', 'ῼ'.swapcase
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
    check_downcase_properties   "yuki\u0307hi\u0307ro matsumoto (matz)", 'YUKİHİRO MATSUMOTO (MATZ)'
  end

  def test_greek
    check_downcase_properties   'αβγδεζηθικλμνξοπρστυφχψω', 'ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ'
    check_upcase_properties     'ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ', 'αβγδεζηθικλμνξοπρστυφχψω'
  end

  # This test checks against problems when changing the order of mapping results
  # in some of the entries of the unfolding table (related to
  # https://bugs.ruby-lang.org/issues/12990).
  def test_reorder_unfold
    # GREEK SMALL LETTER IOTA
    assert_equal 0, "\u03B9" =~ /\u0345/i
    assert_equal 0, "\u0345" =~ /\u03B9/i
    assert_equal 0, "\u03B9" =~ /\u0399/i
    assert_equal 0, "\u0399" =~ /\u03B9/i
    assert_equal 0, "\u03B9" =~ /\u1fbe/i
    assert_equal 0, "\u1fbe" =~ /\u03B9/i

    # GREEK SMALL LETTER MU
    assert_equal 0, "\u03BC" =~ /\u00B5/i
    assert_equal 0, "\u00B5" =~ /\u03BC/i
    assert_equal 0, "\u03BC" =~ /\u039C/i
    assert_equal 0, "\u039C" =~ /\u03BC/i

    # CYRILLIC SMALL LETTER MONOGRAPH UK
    assert_equal 0, "\uA64B" =~ /\u1c88/i
    assert_equal 0, "\u1c88" =~ /\uA64B/i
    assert_equal 0, "\uA64B" =~ /\ua64A/i
    assert_equal 0, "\ua64A" =~ /\uA64B/i
  end

  def no_longer_a_test_buffer_allocations
    assert_equal 'TURKISH*ı'*10, ('I'*10).downcase(:turkic)
    assert_equal 'TURKISH*ı'*100, ('I'*100).downcase(:turkic)
    assert_equal 'TURKISH*ı'*1_000, ('I'*1_000).downcase(:turkic)
    assert_equal 'TURKISH*ı'*10_000, ('I'*10_000).downcase(:turkic)
    assert_equal 'TURKISH*ı'*100_000, ('I'*100_000).downcase(:turkic)
    assert_equal 'TURKISH*ı'*1_000_000, ('I'*1_000_000).downcase(:turkic)
  end
end
