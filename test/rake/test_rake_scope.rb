require File.expand_path('../helper', __FILE__)

class TestRakeScope < Rake::TestCase
  include Rake

  def test_path_against_empty_scope
    scope = Scope.make
    assert_equal scope, Scope::EMPTY
    assert_equal scope.path, ""
  end

  def test_path_against_one_element
    scope = Scope.make(:one)
    assert_equal "one", scope.path
  end

  def test_path_against_two_elements
    scope = Scope.make(:inner, :outer)
    assert_equal "outer:inner", scope.path
  end

  def test_path_with_task_name
    scope = Scope.make(:inner, :outer)
    assert_equal "outer:inner:task", scope.path_with_task_name("task")
  end

  def test_path_with_task_name_against_empty_scope
    scope = Scope.make
    assert_equal "task", scope.path_with_task_name("task")
  end

  def test_conj_against_two_elements
    scope = Scope.make.conj("B").conj("A")
    assert_equal Scope.make("A", "B"), scope
  end

  def test_trim
    scope = Scope.make("A", "B")
    assert_equal scope, scope.trim(0)
    assert_equal scope.tail, scope.trim(1)
    assert_equal scope.tail.tail, scope.trim(2)
    assert_equal scope.tail.tail, scope.trim(3)
  end
end
