require 'test/unit'

class TestForTestRedefinition < Test::Unit::TestCase
  def test_redefinition
    skip "do nothing (1)"
  end

  def test_redefinition
    skip "do nothing (2)"
  end
end
