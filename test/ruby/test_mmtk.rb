# frozen_string_literal: true
#
# This set of tests can be run with:
# make test-all TESTS='test/ruby/test_mmtk.rb' RUN_OPTS="--mmtk"

require 'test/unit'
require 'envutil'
require 'tmpdir'

return unless defined?(GC::MMTk.enabled?) && GC::MMTk.enabled?

class TestMMTk < Test::Unit::TestCase
  def test_description
    assert_includes(RUBY_DESCRIPTION, '+MMTk')
  end

  ENABLE_OPTIONS = [
    ['--mmtk'],
    ["--mmtk-plan=#{GC::MMTk.plan_name}"],
    ['--mmtk-max-heap=1024000'],
    ['--enable-mmtk'],
    ['--enable=mmtk'],

    ['--disable-mmtk', '--mmtk'],
    ['--disable-mmtk', '--enable-mmtk'],
    ['--disable-mmtk', '--enable=mmtk'],
    ['--disable-mmtk', "--mmtk-plan=#{GC::MMTk.plan_name}"],
    ['--disable-mmtk', '--mmtk-max-heap=1024000'],

    ['--disable=mmtk', '--mmtk'],
    ['--disable=mmtk', '--enable-mmtk'],
    ['--disable=mmtk', '--enable=mmtk'],
    ['--disable=mmtk', "--mmtk-plan=#{GC::MMTk.plan_name}"],
    ['--disable=mmtk', '--mmtk-max-heap=1024000']
  ]

  def test_enable
    ENABLE_OPTIONS.each do |version_args|
      assert_in_out_err(['--version'] + version_args) do |stdout, stderr|
        assert_equal(RUBY_DESCRIPTION, stdout.first)
        assert_equal([], stderr)
      end
    end
  end

  def test_enable_from_rubyopt
    ENABLE_OPTIONS.each do |version_args|
      mmtk_child_env = {'RUBYOPT' => version_args.join(' ')}
      assert_in_out_err([mmtk_child_env, '--version'], '') do |stdout, stderr|
        assert_equal(RUBY_DESCRIPTION, stdout.first)
        assert_equal([], stderr)
      end
    end
  end

  def test_invalid_flags
    assert_in_out_err('--mmtk-', '', [], /invalid option --mmtk-/)
    assert_in_out_err('--mmtkhello', '', [], /invalid option --mmtkhello/)
  end

  def test_args
    assert_in_out_err('--mmtk-plan', '', [], /--mmtk-plan needs an argument/)
    assert_in_out_err('--mmtk-plan=', '', [], /--mmtk-plan needs an argument/)
    assert_in_out_err('--mmtk-max-heap', '', [], /--mmtk-max-heap needs an argument/)
    assert_in_out_err('--mmtk-max-heap=', '', [], /--mmtk-max-heap needs an argument/)
  end

  def test_arg_after_script
    Tempfile.create(["test_ignore_after_script", ".rb"]) do |t|
      t.puts "p ARGV"
      t.close
      assert_in_out_err([t.path, '--mmtk'], '', [["--mmtk"].inspect])
    end
  end

  def test_mmtk_plan_env_var
    assert_in_out_err([{'MMTK_PLAN' => 'NoGC'}, '-e puts GC::MMTk.plan_name'], '', ['NoGC'])
  end

  def test_third_party_max_heap_env_var
    assert_in_out_err([{'THIRD_PARTY_HEAP_LIMIT' => '1024000'}, '-e p GC.stat(:mmtk_total_bytes)'], '', ['1024000'])
  end

  def test_enabled
    assert_in_out_err(['-e p GC::MMTk.enabled?'], '', ['false'])
    assert_in_out_err(['--mmtk', '-e p GC::MMTk.enabled?'], '', ['true'])
  end

  def test_plan_name
    assert_in_out_err(['--mmtk-plan=NoGC', '-e puts GC::MMTk.plan_name'], '', ['NoGC'])
    assert_in_out_err(['--mmtk-plan=MarkSweep', '-e puts GC::MMTk.plan_name'], '', ['MarkSweep'])
  end

  def test_max_heap
    assert_in_out_err(['--mmtk-max-heap=1024000', '-e p GC.stat(:mmtk_total_bytes)'], '', ['1024000'])
    assert_in_out_err(['--mmtk-max-heap=1000KiB', '-e p GC.stat(:mmtk_total_bytes)'], '', ['1024000'])
    assert_in_out_err(['--mmtk-max-heap=1MiB', '-e p GC.stat(:mmtk_total_bytes)'], '', ['1048576'])
  end

  def test_gc_stat
    assert_equal(GC.stat(:mmtk_free_bytes).class, Integer)
    assert_equal(GC.stat(:mmtk_total_bytes).class, Integer)
    assert_equal(GC.stat(:mmtk_used_bytes).class, Integer)
    assert_equal(GC.stat(:mmtk_starting_heap_address).class, Integer)
    assert_equal(GC.stat(:mmtk_last_heap_address).class, Integer)
    assert_operator(GC.stat(:mmtk_last_heap_address), :>, GC.stat(:mmtk_starting_heap_address))
    assert_operator(GC.stat(:mmtk_free_bytes), :<=, GC.stat(:mmtk_total_bytes))
    assert_operator(GC.stat(:mmtk_used_bytes), :<=, GC.stat(:mmtk_total_bytes))
  end
end
