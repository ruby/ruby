# Copyright © 2016 Kimihito Matsui (松井 仁人) and Martin J. Dürst (duerst@it.aoyama.ac.jp)

require "test/unit"

# preliminary tests, using :lithuanian as a guard
# to test new implementation strategy
class TestCaseMappingPreliminary < Test::Unit::TestCase
  def test_case_mapping_preliminary
    assert_equal 'yukihiro matsumoto (matz)',
                 'Yukihiro MATSUMOTO (MATZ)'.downcase(:lithuanian)
    assert_equal 'matsumoto yukTURKISH*ıhTURKISH*ıro (matz)',
                 'MATSUMOTO YUKIHIRO (MATZ)'.downcase(:turkic, :lithuanian)
  end

  def test_buffer_allocations
    assert_equal 'TURKISH*ı'*10, ('I'*10).downcase(:turkic, :lithuanian)
    assert_equal 'TURKISH*ı'*100, ('I'*100).downcase(:turkic, :lithuanian)
    assert_equal 'TURKISH*ı'*1_000, ('I'*1_000).downcase(:turkic, :lithuanian)
    assert_equal 'TURKISH*ı'*10_000, ('I'*10_000).downcase(:turkic, :lithuanian)
    assert_equal 'TURKISH*ı'*100_000, ('I'*100_000).downcase(:turkic, :lithuanian)
    assert_equal 'TURKISH*ı'*1_000_000, ('I'*1_000_000).downcase(:turkic, :lithuanian)
  end
end
