# frozen_string_literal: true
#
# This set of tests can be run with:
# make test-all TESTS='test/ruby/test_yjit_exit_locations.rb'

require 'test/unit'
require 'envutil'
require 'tmpdir'
require_relative '../lib/jit_support'

return unless JITSupport.yjit_supported?

# Tests for YJIT with assertions on tracing exits
# insipired by the MJIT tests in test/ruby/test_yjit.rb
class TestYJITExitLocations < Test::Unit::TestCase
  def test_yjit_trace_exits_and_v_no_error
    _stdout, stderr, _status = EnvUtil.invoke_ruby(%w(-v --yjit-trace-exits), '', true, true)
    refute_includes(stderr, "NoMethodError")
  end

  def test_trace_exits_setclassvariable
    script = 'class Foo; def self.foo; @@foo = 1; end; end; Foo.foo'
    assert_exit_locations(script)
  end

  def test_trace_exits_putobject
    assert_exit_locations('true')
    assert_exit_locations('123')
    assert_exit_locations(':foo')
  end

  def test_trace_exits_opt_not
    assert_exit_locations('!false')
    assert_exit_locations('!nil')
    assert_exit_locations('!true')
    assert_exit_locations('![]')
  end

  private

  def assert_exit_locations(test_script)
    write_results = <<~RUBY
      IO.open(3).write Marshal.dump({
        enabled: RubyVM::YJIT.trace_exit_locations_enabled?,
        exit_locations: RubyVM::YJIT.exit_locations
      })
    RUBY

    script = <<~RUBY
      _test_proc = -> {
        #{test_script}
      }
      result = _test_proc.call
      #{write_results}
    RUBY

    run_script = eval_with_jit(script)
    # If stats are disabled when configuring, --yjit-exit-locations
    # can't be true. We don't want to check if exit_locations hash
    # is not empty because that could indicate a bug in the exit
    # locations collection.
    return unless run_script[:enabled]
    exit_locations = run_script[:exit_locations]

    assert exit_locations.key?(:raw)
    assert exit_locations.key?(:frames)
    assert exit_locations.key?(:lines)
    assert exit_locations.key?(:samples)
    assert exit_locations.key?(:missed_samples)
    assert exit_locations.key?(:gc_samples)

    assert_equal 0, exit_locations[:missed_samples]
    assert_equal 0, exit_locations[:gc_samples]

    assert_not_empty exit_locations[:raw]
    assert_not_empty exit_locations[:frames]
    assert_not_empty exit_locations[:lines]

    exit_locations[:frames].each do |frame_id, frame|
      assert frame.key?(:name)
      assert frame.key?(:file)
      assert frame.key?(:samples)
      assert frame.key?(:total_samples)
      assert frame.key?(:edges)
    end
  end

  def eval_with_jit(script)
    args = [
      "--disable-gems",
      "--yjit-call-threshold=1",
      "--yjit-trace-exits"
    ]
    args << "-e" << script_shell_encode(script)
    stats_r, stats_w = IO.pipe
    _out, _err, _status = EnvUtil.invoke_ruby(args,
                                              '', true, true, timeout: 1000, ios: { 3 => stats_w }
                                             )
    stats_w.close
    stats = stats_r.read
    stats = Marshal.load(stats) if !stats.empty?
    stats_r.close
    stats
  end

  def script_shell_encode(s)
    # We can't pass utf-8-encoded characters directly in a shell arg. But we can use Ruby \u constants.
    s.chars.map { |c| c.ascii_only? ? c : "\\u%x" % c.codepoints[0] }.join
  end
end
