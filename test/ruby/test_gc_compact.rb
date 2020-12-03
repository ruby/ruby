# frozen_string_literal: true
require 'test/unit'
require 'fiddle'
require 'etc'

class TestGCCompact < Test::Unit::TestCase
  class AutoCompact < Test::Unit::TestCase
    def setup
      skip "autocompact not supported on this platform" unless supports_auto_compact?
      super
    end

    def test_enable_autocompact
      before = GC.auto_compact
      GC.auto_compact = true
      assert GC.auto_compact
    ensure
      GC.auto_compact = before
    end

    def test_disable_autocompact
      before = GC.auto_compact
      GC.auto_compact = false
      refute GC.auto_compact
    ensure
      GC.auto_compact = before
    end

    def test_major_compacts
      before = GC.auto_compact
      GC.auto_compact = true
      compact = GC.stat :compact_count
      GC.start
      assert_operator GC.stat(:compact_count), :>, compact
    ensure
      GC.auto_compact = before
    end

    def test_implicit_compaction_does_something
      before = GC.auto_compact
      list = []
      list2 = []

      # Try to make some fragmentation
      500.times {
        list << Object.new
        Object.new
        Object.new
      }
      count = GC.stat :compact_count
      GC.auto_compact = true
      loop do
        break if count < GC.stat(:compact_count)
        list2 << Object.new
      end
      compact_stats = GC.latest_compact_info
      refute_predicate compact_stats[:considered], :empty?
      refute_predicate compact_stats[:moved], :empty?
    ensure
      GC.auto_compact = before
    end

    private

    def supports_auto_compact?
      return true unless defined?(Etc::SC_PAGE_SIZE)

      begin
        return GC::INTERNAL_CONSTANTS[:HEAP_PAGE_SIZE] % Etc.sysconf(Etc::SC_PAGE_SIZE) == 0
      rescue NotImplementedError
      rescue ArgumentError
      end

      true
    end
  end

  def os_page_size
    return true unless defined?(Etc::SC_PAGE_SIZE)
  end

  def test_gc_compact_stats
    list = []

    # Try to make some fragmentation
    500.times {
      list << Object.new
      Object.new
      Object.new
    }
    compact_stats = GC.compact
    refute_predicate compact_stats[:considered], :empty?
    refute_predicate compact_stats[:moved], :empty?
  end

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
    GC.verify_compaction_references(double_heap: false)
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
