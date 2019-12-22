# frozen_string_literal: true
require 'test/unit'
require 'fiddle'

class TestGCCompact < Test::Unit::TestCase
  def memory_location(obj)
    (Fiddle.dlwrap(obj) >> 1)
  end

  def big_list(level = 10)
    if level > 0
      big_list(level - 1)
    else
      1000.times.map {
        # try to make some empty slots by allocating an object and discarding
        Object.new
        Object.new
      } # likely next to each other
    end
  end

  # Find an object that's allocated in a slot that had a previous
  # tenant, and that tenant moved and is still alive
  def find_object_in_recycled_slot(addresses)
    new_object = nil

    100_000.times do
      new_object = Object.new
      if addresses.index memory_location(new_object)
        break
      end
    end

    new_object
  end

  def test_complex_hash_keys
    list_of_objects = big_list
    hash = list_of_objects.hash
    GC.verify_compaction_references(toward: :empty)
    assert_equal hash, list_of_objects.hash
  end

  def walk_ast ast
    children = ast.children.grep(RubyVM::AbstractSyntaxTree::Node)
    children.each do |child|
      assert child.type
      walk_ast child
    end
  end

  def test_ast_compacts
    ast = RubyVM::AbstractSyntaxTree.parse_file __FILE__
    assert GC.compact
    walk_ast ast
  end

  def test_compact_count
    count = GC.stat(:compact_count)
    GC.compact
    assert_equal count + 1, GC.stat(:compact_count)
  end
end
