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
    GC.verify_compaction_references(double_heap: false)
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

  def test_moving_strings_between_size_pools
    assert_separately([], "#{<<~"begin;"}\n#{<<~"end;"}", timeout: 10, signal: :SEGV)
    begin;
      moveables = []
      small_slots = []
      large_slots = []

      # Ensure fragmentation in the large heap
      base_slot_size = GC.stat_heap[0].fetch(:slot_size)
      500.times {
        String.new(+"a" * base_slot_size).downcase
        large_slots << String.new(+"a" * base_slot_size).downcase
      }

      # Ensure fragmentation in the smaller heap
      500.times {
        small_slots << Object.new
        Object.new
      }

      500.times {
        # strings are created as shared strings when initialized from literals
        # use downcase to force the creation of an embedded string (it calls
        # rb_str_new internally)
        moveables << String.new(+"a" * base_slot_size).downcase

        moveables << String.new("a").downcase
      }
      moveables.map { |s| s << ("bc" * base_slot_size) }
      moveables.map { |s| s.squeeze! }
      stats = GC.compact

      moved_strings = (stats.dig(:moved_up, :T_STRING) || 0) +
        (stats.dig(:moved_down, :T_STRING) || 0)

      assert_operator(moved_strings, :>, 0)
    end;
  end
end
