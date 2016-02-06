# Copyright © 2016 Kimihito Matsui (松井 仁人) and Martin J. Dürst (duerst@it.aoyama.ac.jp)

require "test/unit"

# preliminary tests, using :lithuanian as a guard
# to test new implementation strategy
class TestCaseMappingPreliminary < Test::Unit::TestCase
  # checks, including idempotence and non-modification; not always guaranteed
  def check_upcase_properties(expected, start, *flags)
    assert_equal expected, start.upcase(*flags)
    temp = start
    assert_equal expected, temp.upcase!(*flags)
    assert_equal expected, expected.upcase(*flags)
    temp = expected
    assert_nil   temp.upcase!(*flags)
  end

  def check_downcase_properties(expected, start, *flags)
    assert_equal expected, start.downcase(*flags)
    temp = start
    assert_equal expected, temp.downcase!(*flags)
    assert_equal expected, expected.downcase(*flags)
    temp = expected
    assert_nil   temp.downcase!(*flags)
  end

  def check_capitalize_properties(expected, start, *flags)
    assert_equal expected, start.capitalize(*flags)
    temp = start
    assert_equal expected, temp.capitalize!(*flags)
    assert_equal expected, expected.capitalize(*flags)
    temp = expected
    assert_nil   temp.capitalize!(*flags)
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
  end

  def test_turcic
    check_downcase_properties   'yukihiro matsumoto (matz)', 'Yukihiro MATSUMOTO (MATZ)', :turkic
    check_upcase_properties     'YUKİHİRO MATSUMOTO (MATZ)', 'Yukihiro Matsumoto (matz)', :turkic
    check_downcase_properties   "yuki\u0307hi\u0307ro matsumoto (matz)", 'YUKİHİRO MATSUMOTO (MATZ)', :lithuanian
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
