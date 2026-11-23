# frozen_string_literal: false
require 'test/unit'

class TestGCPermanent < Test::Unit::TestCase
  def setup
    omit "default GC only" unless GC.config.key?(:permanent_generation)
    omit "counts assume no automatic promotion" if ENV["RUBY_GC_PERMANENT_AUTO_PROMOTE"]
  end

  def test_warmup_promotes_only_when_enabled
    assert_separately([], <<~RUBY)
      $keep = Array.new(10_000) { |i| "boot \#{i}" }
      Process.warmup
      assert_equal 0, GC.stat(:permanent_objects)

      GC.config(permanent_generation: true)
      assert_true GC.config[:permanent_generation]
      Process.warmup
      assert_operator GC.stat(:permanent_objects), :>=, 10_000
      assert_equal 1, GC.stat(:permanent_promote_count)
      assert_true ObjectSpace.dump($keep).include?('"permanent":true') if defined?(ObjectSpace.dump)
      GC.verify_internal_consistency
    RUBY
  end

  def test_partial_major_keeps_new_references_from_permanent_objects
    assert_separately([], <<~RUBY)
      GC.config(permanent_generation: true)
      class Holder; attr_accessor :v; end
      $holders = Array.new(500) { Holder.new }
      $ary = Array.new(500)
      $hash = {}
      module Boot; end
      Process.warmup
      perm = GC.stat(:permanent_objects)
      assert_operator perm, :>, 0

      $holders.each_with_index { |h, i| h.v = "h\#{i}" }
      500.times { |i| $ary[i] = [i, "a\#{i}"] }
      500.times { |i| $hash[i] = { i => "x\#{i}" } }
      Boot.const_set(:LATE, "late constant")
      Boot.define_singleton_method(:late) { "late method" }
      Boot.instance_variable_set(:@late, Object.new)

      3.times { Array.new(10_000) { "garbage" }; GC.start }
      GC.verify_internal_consistency

      assert_operator GC.stat(:permanent_partial_major_count), :>=, 3
      assert_equal 0, GC.stat(:permanent_full_major_count)
      assert_equal perm, GC.stat(:permanent_objects)
      $holders.each_with_index { |h, i| assert_equal "h\#{i}", h.v }
      500.times { |i| assert_equal [i, "a\#{i}"], $ary[i] }
      500.times { |i| assert_equal({ i => "x\#{i}" }, $hash[i]) }
      assert_equal "late constant", Boot::LATE
      assert_equal "late method", Boot.late
      assert_kind_of Object, Boot.instance_variable_get(:@late)
    RUBY
  end

  def test_partial_major_frees_young_garbage
    assert_separately([], <<~RUBY)
      GC.config(permanent_generation: true)
      Process.warmup
      GC.start
      before = GC.stat(:total_freed_objects)
      100_000.times { Object.new }
      GC.start
      assert_operator GC.stat(:total_freed_objects) - before, :>=, 90_000
    RUBY
  end

  def test_weak_references_held_by_permanent_objects
    assert_separately([], <<~RUBY)
      GC.config(permanent_generation: true)
      $wm = ObjectSpace::WeakMap.new
      $wkm = ObjectSpace::WeakKeyMap.new
      Process.warmup
      assert_true ObjectSpace.dump($wm).include?('"permanent":true') if defined?(ObjectSpace.dump)

      100.times { |i| $wm["k\#{i}"] = Object.new }
      100.times { $wkm[Object.new] = 1 }
      GC.start
      GC.start
      GC.verify_internal_consistency
      assert_operator GC.stat(:permanent_partial_major_count), :>=, 2
      assert_operator $wm.size, :<, 100
      assert_operator $wkm.inspect.size, :<, 1000
    RUBY
  end

  def test_full_collection_frees_dead_permanent_objects
    assert_separately([], <<~RUBY)
      GC.config(permanent_generation: true)
      $keep = Array.new(20_000) { |i| "boot \#{i}" }
      Process.warmup
      perm = GC.stat(:permanent_objects)
      $keep = nil
      GC.start
      assert_equal perm, GC.stat(:permanent_objects)

      GC.config(permanent_collect: true)
      GC.start
      assert_equal 1, GC.stat(:permanent_full_major_count)
      assert_operator GC.stat(:permanent_objects), :<=, perm - 20_000
      GC.verify_internal_consistency
    RUBY
  end

  def test_promote_again_without_warmup
    assert_separately([], <<~RUBY)
      GC.config(permanent_generation: true)
      Process.warmup
      perm = GC.stat(:permanent_objects)
      $late = Array.new(5_000) { |i| "late \#{i}" }
      4.times { GC.start }
      GC.config(permanent_promote: true)
      assert_operator GC.stat(:permanent_objects), :>=, perm + 5_000
      assert_equal 2, GC.stat(:permanent_promote_count)
      GC.verify_internal_consistency
      GC.start
      GC.verify_internal_consistency
      5_000.times { |i| assert_equal "late \#{i}", $late[i] }
    RUBY
  end

  def test_full_mark_interval
    assert_separately([], <<~RUBY)
      GC.config(permanent_generation: true, permanent_full_mark_interval: 3)
      Process.warmup
      6.times { GC.start }
      assert_equal 2, GC.stat(:permanent_full_major_count)
      assert_equal 4, GC.stat(:permanent_partial_major_count)
    RUBY
  end

  def test_compaction
    omit "GC compaction not supported on this platform" unless GC.respond_to?(:compact)
    assert_separately([], <<~RUBY)
      GC.config(permanent_generation: true)
      $objs = Array.new(5_000) { |i| [i, "s\#{i}"] }
      Process.warmup
      $objs.each_with_index { |o, i| o << "late\#{i}" }
      GC.compact
      GC.verify_internal_consistency
      GC.start
      GC.verify_internal_consistency
      $objs.each_with_index { |o, i| assert_equal [i, "s\#{i}", "late\#{i}"], o }
      GC.verify_compaction_references(expand_heap: true, toward: :empty)
      GC.verify_internal_consistency
      $objs.each_with_index { |o, i| assert_equal [i, "s\#{i}", "late\#{i}"], o }
    RUBY
  end

  def test_stress_after_warmup
    assert_separately([], <<~RUBY, timeout: 60)
      GC.config(permanent_generation: true)
      $a = Array.new(100) { [] }
      $h = {}
      Process.warmup
      GC.stress = true
      300.times do |i|
        $a[i % 100] << "s\#{i}"
        $h[i % 7] = [i]
        Object.const_get(:Comparable).instance_variable_set(:@x, Object.new)
      end
      GC.stress = false
      GC.verify_internal_consistency
      300.times { |i| assert_include $a[i % 100], "s\#{i}" }
    RUBY
  end

  def test_disable_dissolves
    assert_separately([], <<~RUBY)
      GC.config(permanent_generation: true)
      $keep = Array.new(1_000) { "x" }
      Process.warmup
      assert_operator GC.stat(:permanent_objects), :>, 0
      GC.config(permanent_generation: false)
      assert_equal 0, GC.stat(:permanent_objects)
      GC.start
      GC.verify_internal_consistency
    RUBY
  end

  def test_multiple_ractors_use_full_majors
    assert_separately([], <<~RUBY)
      Warning[:experimental] = false
      GC.config(permanent_generation: true)
      $keep = Array.new(1_000) { "x" }
      Process.warmup
      r = Ractor.new { Ractor.receive }
      full = GC.stat(:permanent_full_major_count)
      GC.start(global: false)
      assert_equal full + 1, GC.stat(:permanent_full_major_count)
      r.send(1)
      r.join
      GC.start
      GC.verify_internal_consistency
    RUBY
  end
end
