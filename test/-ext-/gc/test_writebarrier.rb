# frozen_string_literal: false
require 'test/unit'

class Test_GCWriteBarrier < Test::Unit::TestCase
  N = 1000

  # Young WB-unprotected objects never age, so every GC re-marks them; they must be
  # counted by both minor and major GCs.
  def test_collectible_wb_unprotected_objects_young
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately(%W[-W0 -r-test-/gc/writebarrier], <<~RUBY)
      objs = Array.new(#{N}) { Bug::GC::WriteBarrier.unprotect(Object.new) }

      GC.start(full_mark: false)
      assert_operator GC.stat(:collectible_wb_unprotected_objects), :>=, #{N}

      GC.start
      assert_operator GC.stat(:collectible_wb_unprotected_objects), :>=, #{N}
    RUBY
  end

  # Unprotecting an old object makes it uncollectible: a minor GC must count it in
  # remembered_wb_unprotected_objects, not here, until a major GC turns it collectible.
  def test_collectible_wb_unprotected_objects_excludes_uncollectible
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately(%W[-W0 -r-test-/gc/writebarrier], <<~RUBY)
      objs = Array.new(#{N}) { Object.new }
      4.times { GC.start }

      GC.start(full_mark: false)
      base = GC.stat(:collectible_wb_unprotected_objects)

      objs.each { |o| Bug::GC::WriteBarrier.unprotect(o) }
      assert_operator GC.stat(:remembered_wb_unprotected_objects), :>=, #{N}

      GC.start(full_mark: false)
      assert_operator GC.stat(:collectible_wb_unprotected_objects), :<, base + #{N}

      GC.start
      assert_operator GC.stat(:collectible_wb_unprotected_objects), :>=, #{N}
    RUBY
  end
end
