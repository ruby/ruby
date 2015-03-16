require File.expand_path('../helper', __FILE__)

class TestLinkedList < Rake::TestCase
  include Rake

  def test_empty_list
    empty = LinkedList::EMPTY
    assert empty.empty?, "should be empty"
  end

  def test_list_with_one_item
    list = LinkedList.make(:one)
    assert ! list.empty?, "should not be empty"
    assert_equal :one, list.head
    assert_equal LinkedList::EMPTY, list.tail
  end

  def test_make_with_no_arguments
    empty = LinkedList.make()
    assert_equal LinkedList::EMPTY, empty
  end

  def test_make_with_one_argument
    list = LinkedList.make(:one)
    assert ! list.empty?
    assert_equal :one, list.head
    assert_equal LinkedList::EMPTY, list.tail
  end

  def test_make_with_two_arguments
    list = LinkedList.make(:one, :two)
    assert ! list.empty?
    assert_equal :one, list.head
    assert_equal :two, list.tail.head
    assert_equal LinkedList::EMPTY, list.tail.tail
  end

  def test_list_with_several_items
    list = LinkedList.make(:one, :two, :three)

    assert ! list.empty?, "should not be empty"
    assert_equal :one, list.head
    assert_equal :two, list.tail.head
    assert_equal :three, list.tail.tail.head
    assert_equal LinkedList::EMPTY, list.tail.tail.tail
  end

  def test_lists_are_structurally_equivalent
    list = LinkedList.make(1, 2, 3)
    same = LinkedList.make(1, 2, 3)
    diff = LinkedList.make(1, 2, 4)
    short = LinkedList.make(1, 2)

    assert_equal list, same
    refute_equal list, diff
    refute_equal list, short
    refute_equal short, list
  end

  def test_conversion_to_string
    list = LinkedList.make(:one, :two, :three)
    assert_equal "LL(one, two, three)", list.to_s
    assert_equal "LL()", LinkedList.make().to_s
  end

  def test_conversion_with_inspect
    list = LinkedList.make(:one, :two, :three)
    assert_equal "LL(:one, :two, :three)", list.inspect
    assert_equal "LL()", LinkedList.make().inspect
  end

  def test_lists_are_enumerable
    list = LinkedList.make(1, 2, 3)
    new_list = list.map { |item| item + 10 }
    expected = [11, 12, 13]
    assert_equal expected, new_list
  end

  def test_conjunction
    list = LinkedList.make.conj("C").conj("B").conj("A")
    assert_equal LinkedList.make("A", "B", "C"), list
  end

end
