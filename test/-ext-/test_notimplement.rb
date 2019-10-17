# frozen_string_literal: false
require '-test-/notimplement'

class Test_NotImplement < Test::Unit::TestCase
  def test_funcall_notimplement
    bug3662 = '[ruby-dev:41953]'
    assert_raise(NotImplementedError, bug3662) {
      Bug.funcall(:notimplement)
    }
    assert_raise(NotImplementedError) {
      Bug::NotImplement.new.notimplement
    }
  end

  def test_respond_to
    assert_not_respond_to(Bug, :notimplement)
    assert_not_respond_to(Bug::NotImplement.new, :notimplement)
  end

  def test_not_method_defined
    assert !Bug::NotImplement.method_defined?(:notimplement)
    assert !Bug::NotImplement.method_defined?(:notimplement, true)
    assert !Bug::NotImplement.method_defined?(:notimplement, false)
  end

  def test_not_private_method_defined
    assert !Bug::NotImplement.private_method_defined?(:notimplement)
    assert !Bug::NotImplement.private_method_defined?(:notimplement, true)
    assert !Bug::NotImplement.private_method_defined?(:notimplement, false)
  end

  def test_not_protected_method_defined
    assert !Bug::NotImplement.protected_method_defined?(:notimplement)
    assert !Bug::NotImplement.protected_method_defined?(:notimplement, true)
    assert !Bug::NotImplement.protected_method_defined?(:notimplement, false)
  end
end
