# frozen_string_literal: false
require '-test-/notimplement'

class TestNotImplement < Test::Unit::TestCase
  def test_funcall_notimplement
    bug3662 = '[ruby-dev:41953]'
    assert_raise(NotImplementedError, bug3662) {
      Bug.funcall(:notimplement)
    }
  end

  def test_respond_to
    assert_not_respond_to(Bug, :notimplement)
  end
end
