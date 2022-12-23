# frozen_string_literal: true
require 'test/unit'
require 'fiddle'
require 'etc'

if RUBY_PLATFORM =~ /s390x/
  warn "Currently, it is known that the compaction does not work well on s390x; contribution is welcome https://github.com/ruby/ruby/pull/5077"
  return
end

class TestGCCompact < Test::Unit::TestCase
  module CompactionSupportInspector
    def supports_auto_compact?
      GC::OPTS.include?("GC_COMPACTION_SUPPORTED")
    end
  end

  module OmitUnlessCompactSupported
    include CompactionSupportInspector

    def setup
      omit "autocompact not supported on this platform" unless supports_auto_compact?
      super
    end
  end

  include OmitUnlessCompactSupported

  class AutoCompact < Test::Unit::TestCase
    include OmitUnlessCompactSupported

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
      n = 1_000_000
      n.times do
        break if count < GC.stat(:compact_count)
        list2 << Object.new
      end and omit "implicit compaction didn't happen within #{n} objects"
      compact_stats = GC.latest_compact_info
      refute_predicate compact_stats[:considered], :empty?
      refute_predicate compact_stats[:moved], :empty?
    ensure
      GC.auto_compact = before
    end
  end

  class CompactMethodsNotImplemented < Test::Unit::TestCase
    include CompactionSupportInspector

    def assert_not_implemented(method, *args)
      omit "autocompact is supported on this platform" if supports_auto_compact?

      assert_raise(NotImplementedError) { GC.send(method, *args) }
      refute(GC.respond_to?(method), "GC.#{method} should be defined as rb_f_notimplement")
    end

    def test_gc_compact_not_implemented
      assert_not_implemented(:compact)
    end

    def test_gc_auto_compact_get_not_implemented
      assert_not_implemented(:auto_compact)
    end

    def test_gc_auto_compact_set_not_implemented
      assert_not_implemented(:auto_compact=, true)
    end

    def test_gc_latest_compact_info_not_implemented
      assert_not_implemented(:latest_compact_info)
    end

    def test_gc_verify_compaction_references_not_implemented
      assert_not_implemented(:verify_compaction_references)
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
    GC.verify_compaction_references(expand_heap: false)
    assert_equal hash, list_of_objects.hash
  end

  def test_ast_compacts
    assert_separately([], "#{<<~"begin;"}\n#{<<~"end;"}", timeout: 10, signal: :SEGV)
    begin;
      def walk_ast ast
        children = ast.children.grep(RubyVM::AbstractSyntaxTree::Node)
        children.each do |child|
          assert child.type
          walk_ast child
        end
      end
      ast = RubyVM::AbstractSyntaxTree.parse_file #{__FILE__.dump}
      assert GC.compact
      walk_ast ast
    end;
  end

  def test_compact_count
    count = GC.stat(:compact_count)
    GC.compact
    assert_equal count + 1, GC.stat(:compact_count)
  end

  def test_compacting_from_trace_point
    obj = Object.new
    def obj.tracee
      :ret # expected to emit both line and call event from one instruction
    end

    results = []
    TracePoint.new(:call, :line) do |tp|
      results << tp.event
      GC.verify_compaction_references
    end.enable(target: obj.method(:tracee)) do
      obj.tracee
    end

    assert_equal([:call, :line], results)
  end

  def test_updating_references_for_heap_allocated_shared_arrays
    assert_separately(%w[-robjspace], "#{<<~"begin;"}\n#{<<~"end;"}", timeout: 10, signal: :SEGV)
    begin;
      ary = []
      50.times { |i| ary << i }

      # Pointer in slice should point to buffer of ary
      slice = ary[10..40]

      # Check that slice is pointing to buffer of ary
      assert_include(ObjectSpace.dump(slice), '"shared":true')

      # Run compaction to re-embed ary
      GC.verify_compaction_references(expand_heap: true, toward: :empty)

      # Assert that slice is pointer to updated buffer in ary
      assert_equal(10, slice[0])
      # Check that slice is still pointing to buffer of ary
      assert_include(ObjectSpace.dump(slice), '"shared":true')
    end;
  end

  def test_updating_references_for_embed_shared_arrays
    omit if GC::INTERNAL_CONSTANTS[:SIZE_POOL_COUNT] == 1

    assert_separately(%w[-robjspace], "#{<<~"begin;"}\n#{<<~"end;"}", timeout: 10, signal: :SEGV)
    begin;
      ary = Array.new(50)
      50.times { |i| ary[i] = i }

      # Ensure ary is embedded
      assert_include(ObjectSpace.dump(ary), '"embedded":true')

      slice = ary[10..40]

      # Check that slice is pointing to buffer of ary
      assert_include(ObjectSpace.dump(slice), '"shared":true')

      # Run compaction to re-embed ary
      GC.verify_compaction_references(expand_heap: true, toward: :empty)

      # Assert that slice is pointer to updated buffer in ary
      assert_equal(10, slice[0])
      # Check that slice is still pointing to buffer of ary
      assert_include(ObjectSpace.dump(slice), '"shared":true')
    end;
  end

  def test_updating_references_for_heap_allocated_frozen_shared_arrays
    assert_separately(%w[-robjspace], "#{<<~"begin;"}\n#{<<~"end;"}", timeout: 10, signal: :SEGV)
    begin;
      ary = []
      50.times { |i| ary << i }
      # Frozen arrays can become shared root without RARRAY_SHARED_ROOT_FLAG
      ary.freeze

      slice = ary[10..40]

      # Check that slice is pointing to buffer of ary
      assert_include(ObjectSpace.dump(slice), '"shared":true')

      # Run compaction to re-embed ary
      GC.verify_compaction_references(expand_heap: true, toward: :empty)

      # Assert that slice is pointer to updated buffer in ary
      assert_equal(10, slice[0])
      # Check that slice is still pointing to buffer of ary
      assert_include(ObjectSpace.dump(slice), '"shared":true')
    end;
  end

  def test_updating_references_for_embed_frozen_shared_arrays
    omit if GC::INTERNAL_CONSTANTS[:SIZE_POOL_COUNT] == 1

    assert_separately(%w[-robjspace], "#{<<~"begin;"}\n#{<<~"end;"}", timeout: 10, signal: :SEGV)
    begin;
      ary = Array.new(50)
      50.times { |i| ary[i] = i }
      # Frozen arrays can become shared root without RARRAY_SHARED_ROOT_FLAG
      ary.freeze

      # Ensure ary is embedded
      assert_include(ObjectSpace.dump(ary), '"embedded":true')

      slice = ary[10..40]

      # Check that slice is pointing to buffer of ary
      assert_include(ObjectSpace.dump(slice), '"shared":true')

      # Run compaction to re-embed ary
      GC.verify_compaction_references(expand_heap: true, toward: :empty)

      # Assert that slice is pointer to updated buffer in ary
      assert_equal(10, slice[0])
      # Check that slice is still pointing to buffer of ary
      assert_include(ObjectSpace.dump(slice), '"shared":true')
    end;
  end

  def test_moving_arrays_down_size_pools
    omit if GC::INTERNAL_CONSTANTS[:SIZE_POOL_COUNT] == 1

    assert_separately([], "#{<<~"begin;"}\n#{<<~"end;"}", timeout: 10, signal: :SEGV)
    begin;
      ARY_COUNT = 500

      GC.verify_compaction_references(expand_heap: true, toward: :empty)

      arys = ARY_COUNT.times.map do
        ary = "abbbbbbbbbb".chars
        ary.uniq!
      end

      stats = GC.verify_compaction_references(expand_heap: true, toward: :empty)
      assert_operator(stats.dig(:moved_down, :T_ARRAY), :>=, ARY_COUNT)
      assert(arys) # warning: assigned but unused variable - arys
    end;
  end

  def test_moving_arrays_up_size_pools
    omit if GC::INTERNAL_CONSTANTS[:SIZE_POOL_COUNT] == 1

    assert_separately([], "#{<<~"begin;"}\n#{<<~"end;"}", timeout: 10, signal: :SEGV)
    begin;
      ARY_COUNT = 500

      GC.verify_compaction_references(expand_heap: true, toward: :empty)

      ary = "hello".chars
      arys = ARY_COUNT.times.map do
        x = []
        ary.each { |e| x << e }
        x
      end

      stats = GC.verify_compaction_references(expand_heap: true, toward: :empty)
      assert_operator(stats.dig(:moved_up, :T_ARRAY), :>=, ARY_COUNT)
      assert(arys) # warning: assigned but unused variable - arys
    end;
  end

  def test_moving_objects_between_size_pools
    omit if GC::INTERNAL_CONSTANTS[:SIZE_POOL_COUNT] == 1

    assert_separately([], "#{<<~"begin;"}\n#{<<~"end;"}", timeout: 10, signal: :SEGV)
    begin;
      class Foo
        def add_ivars
          10.times do |i|
            instance_variable_set("@foo" + i.to_s, 0)
          end
        end
      end

      OBJ_COUNT = 500

      GC.verify_compaction_references(expand_heap: true, toward: :empty)

      ary = OBJ_COUNT.times.map { Foo.new }
      ary.each(&:add_ivars)

      GC.start
      Foo.new.add_ivars

      stats = GC.verify_compaction_references(expand_heap: true, toward: :empty)

      assert_operator(stats[:moved_up][:T_OBJECT], :>=, OBJ_COUNT)
    end;
  end

  def test_moving_strings_up_size_pools
    omit if GC::INTERNAL_CONSTANTS[:SIZE_POOL_COUNT] == 1

    assert_separately([], "#{<<~"begin;"}\n#{<<~"end;"}", timeout: 10, signal: :SEGV)
    begin;
      STR_COUNT = 500

      GC.verify_compaction_references(expand_heap: true, toward: :empty)

      str = "a" * GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE]
      ary = STR_COUNT.times.map { "" << str }

      stats = GC.verify_compaction_references(expand_heap: true, toward: :empty)

      assert_operator(stats[:moved_up][:T_STRING], :>=, STR_COUNT)
      assert(ary) # warning: assigned but unused variable - ary
    end;
  end

  def test_moving_strings_down_size_pools
    omit if GC::INTERNAL_CONSTANTS[:SIZE_POOL_COUNT] == 1

    assert_separately([], "#{<<~"begin;"}\n#{<<~"end;"}", timeout: 10, signal: :SEGV)
    begin;
      STR_COUNT = 500

      GC.verify_compaction_references(expand_heap: true, toward: :empty)

      ary = STR_COUNT.times.map { ("a" * GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE]).squeeze! }

      stats = GC.verify_compaction_references(expand_heap: true, toward: :empty)

      assert_operator(stats[:moved_down][:T_STRING], :>=, STR_COUNT)
      assert(ary) # warning: assigned but unused variable - ary
    end;
  end
end
