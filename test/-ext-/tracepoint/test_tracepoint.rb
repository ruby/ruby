require 'test/unit'
require '-test-/tracepoint'

class TestTracepointObj < Test::Unit::TestCase
  def test_not_available_from_ruby
    assert_raises ArgumentError do
      TracePoint.trace(:obj_new){}
    end
  end

  def test_tracks_objspace_events
    result = Bug.tracepoint_track_objspace_events{
      99
      'abc'
      v="foobar"
      Object.new
      nil
    }

    newobj_count, free_count, gc_start_count, gc_end_count, *newobjs = *result
    assert_equal 2, newobj_count
    assert_equal 2, newobjs.size
    assert_equal 'foobar', newobjs[0]
    assert_equal Object, newobjs[1].class

    stat1 = {}
    stat2 = {}
    GC.disable
    GC.stat(stat1)
    result = Bug.tracepoint_track_objspace_events{
      GC.enable
      1_000_000.times{''}
      GC.disable
    }
    GC.stat(stat2)
    GC.enable

    newobj_count, free_count, gc_start_count, gc_end_count, *newobjs = *result

    assert_operator stat2[:total_allocated_object] - stat1[:total_allocated_object], :>=, newobj_count
    assert_operator 1_000_000, :<=, newobj_count

    assert_operator stat2[:total_freed_object] - stat1[:total_freed_object], :>=, free_count
    assert_operator stat2[:count] - stat1[:count], :==, gc_start_count

    assert_operator gc_start_count, :>=, gc_end_count
    assert_operator stat2[:count] - stat1[:count] - 1, :<=, gc_end_count
  end
end
