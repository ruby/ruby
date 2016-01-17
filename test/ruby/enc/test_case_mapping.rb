# Copyright © 2016 Kimihito Matsui (松井 仁人) and Martin J. Dürst (duerst@it.aoyama.ac.jp)

require "test/unit"

# preliminary tests, using :lithuanian as a guard
# to test new implementation strategy
class TestCaseMappingPreliminary < Test::Unit::TestCase
  def test_ascii
    assert_equal 'yukihiro matsumoto (matz)',
                 'Yukihiro MATSUMOTO (MATZ)'.downcase(:lithuanian)
    assert_equal 'YUKIHIRO MATSUMOTO (MATZ)',
                 'yukihiro matsumoto (matz)'.upcase(:lithuanian)
    assert_equal 'Yukihiro matsumoto (matz)',
                 'yukihiro MATSUMOTO (MATZ)'.capitalize(:lithuanian)
    assert_equal 'yUKIHIRO matsumoto (MAtz)',
                 'Yukihiro MATSUMOTO (maTZ)'.swapcase(:lithuanian)
  end

  def test_turcic
    assert_equal 'yukihiro matsumoto (matz)',
                 'Yukihiro MATSUMOTO (MATZ)'.downcase(:turkic, :lithuanian)
    assert_equal 'YUKİHİRO MATSUMOTO (MATZ)',
                 'Yukihiro Matsumoto (matz)'.upcase(:turkic, :lithuanian)
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
