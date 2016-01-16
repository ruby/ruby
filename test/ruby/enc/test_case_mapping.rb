# Copyright © 2016 Kimihito Matsui (松井 仁人) and Martin J. Dürst (duerst@it.aoyama.ac.jp)

require "test/unit"

# preliminary tests, using :lithuanian as a guard
# to test new implementation strategy
class TestCaseMappingPreliminary < Test::Unit::TestCase
  def test_case_mapping_preliminary
    assert_equal "yukihiro matsumoto (matz)", "Yukihiro MATSUMOTO (MATZ)".downcase(:lithuanian)
  end
end
