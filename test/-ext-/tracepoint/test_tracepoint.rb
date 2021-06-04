# frozen_string_literal: false
require 'test/unit'
require '-test-/tracepoint'

class TestTracepointObj < Test::Unit::TestCase
  def test_not_available_from_ruby
    assert_raise ArgumentError do
      TracePoint.trace(:obj_new){}
    end
  end

  def test_tracks_objspace_events
    result = EnvUtil.suppress_warning {eval(<<-EOS, nil, __FILE__, __LINE__+1)}
    Bug.tracepoint_track_objspace_events {
      99
      'abc'
      _="foobar"
      nil
    }
    EOS

    newobj_count, free_count, gc_start_count, gc_end_mark_count, gc_end_sweep_count, *newobjs = *result
    assert_equal 1, newobj_count
    assert_equal 1, newobjs.size
    assert_equal 'foobar', newobjs[0]
    assert_operator free_count, :>=, 0
    assert_operator gc_start_count, :==, gc_end_mark_count
    assert_operator gc_start_count, :>=, gc_end_sweep_count
  end

  def test_tracks_objspace_count
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

    newobj_count, free_count, gc_start_count, gc_end_mark_count, gc_end_sweep_count, = *result

    assert_operator stat2[:total_allocated_objects] - stat1[:total_allocated_objects], :>=, newobj_count
    assert_operator 1_000_000, :<=, newobj_count

    assert_operator stat2[:total_freed_objects] + stat2[:heap_final_slots] - stat1[:total_freed_objects], :>=, free_count
    assert_operator stat2[:count] - stat1[:count], :==, gc_start_count

    assert_operator gc_start_count, :==, gc_end_mark_count
    assert_operator gc_start_count, :>=, gc_end_sweep_count
    assert_operator stat2[:count] - stat1[:count] - 1, :<=, gc_end_sweep_count
  end

  def test_tracepoint_specify_normal_and_internal_events
    assert_raise(TypeError){ Bug.tracepoint_specify_normal_and_internal_events }
  end

  def test_after_gc_start_hook_with_GC_stress
    bug8492 = '[ruby-dev:47400] [Bug #8492]: infinite after_gc_start_hook reentrance'
    assert_nothing_raised(Timeout::Error, bug8492) do
      assert_in_out_err(%w[-r-test-/tracepoint], <<-'end;', /\A[1-9]/, timeout: 2)
        count = 0
        hook = proc {count += 1}
        def run(hook)
        stress, GC.stress = GC.stress, false
        Bug.after_gc_start_hook = hook
        begin
          GC.stress = true
          3.times {Object.new}
        ensure
          GC.stress = stress
          Bug.after_gc_start_hook = nil
        end
        end
        run(hook)
        puts count
      end;
    end
  end

  def test_teardown_with_active_GC_end_hook
    assert_separately([], 'require("-test-/tracepoint"); Bug.after_gc_exit_hook = proc {}')
  end

end
