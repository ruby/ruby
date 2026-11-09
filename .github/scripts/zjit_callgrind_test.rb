# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'
require_relative 'zjit_callgrind'

class ZJITCallgrindTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir('zjit-callgrind')
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def profile(name, text, directory = @directory)
    path = File.join(directory, name)
    File.write(path, text)
    path
  end

  def results(directory = @directory, executable = 'base', iterations = [0.1])
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'results.json'), JSON.generate(
      'raw_data' => {executable => {'fib' => {
        'bench' => iterations,
        'command_line' => "valgrind --callgrind-out-file='/runner/results with spaces/callgrind-fib.out.%p' ruby --zjit fib.rb",
      }}}
    ))
  end

  def test_ir_event_need_not_be_first
    path = profile('profile', "events: Dr Ir Dw\nsummary: 7 123 9\n")
    assert_equal 123, ZJITCallgrind.instruction_count(path)
  end

  def test_only_explicit_measured_dump_is_counted
    results
    profile('callgrind-fib.out.123', "events: Ir\nsummary: 999\n")
    profile('callgrind-fib.out.123.1', "events: Ir\nsummary: 123\n")
    assert_equal({'fib' => 123}, ZJITCallgrind.read_counts(@directory, 'base'))
  end

  def test_missing_or_duplicate_dump_fails
    results
    assert_raises(ArgumentError) { ZJITCallgrind.read_counts(@directory, 'base') }
    [123, 456].each do |pid|
      profile("callgrind-fib.out.#{pid}.1", "events: Ir\nsummary: 123\n")
    end
    assert_raises(ArgumentError) { ZJITCallgrind.read_counts(@directory, 'base') }
  end

  def test_invalid_or_empty_profile_fails
    ["events: Dr\nsummary: 5\n", "events: Ir\n", "events: Ir\nsummary: 0\n",
     "events: Dr Ir\nsummary: 5\n", "events: Ir\nsummary: nope\n"].each do |text|
      assert_raises(ArgumentError) { ZJITCallgrind.instruction_count(profile('profile', text)) }
    end
  end

  def test_multiple_measured_iterations_fail
    results(@directory, 'base', [0.1, 0.2])
    profile('callgrind-fib.out.123.1', "events: Ir\nsummary: 123\n")
    assert_raises(ArgumentError) { ZJITCallgrind.read_counts(@directory, 'base') }
  end

  def test_change_direction_and_count_formatting
    text = ZJITCallgrind.report({'fib' => 1000, 'getivar' => 100},
                              {'getivar' => 120, 'fib' => 900}, 'base', 'head', 'bench')
    assert_includes text, '40 warmup iterations, then 1 measured iteration'
    assert_includes text, '| fib | 1,000 | 900 | -10.00% |'
    assert_includes text, '| getivar | 100 | 120 | +20.00% |'
  end

  def test_mismatched_suites_fail
    assert_raises(ArgumentError) { ZJITCallgrind.report({'fib' => 100}, {}, 'base', 'head', 'bench') }
  end

  def test_invalid_benchmark_name_fails
    counts = {'fib | injected' => 100}
    assert_raises(ArgumentError) { ZJITCallgrind.report(counts, counts, 'base', 'head', 'bench') }
  end

  def test_cli
    {'base' => 100, 'pr' => 90}.each do |executable, count|
      directory = File.join(@directory, executable)
      results(directory, executable)
      profile('callgrind-fib.out.123.1', "events: Ir\nsummary: #{count}\n", directory)
    end
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.join(__dir__, 'zjit_callgrind.rb'),
                                           @directory, '--base', 'base-sha', '--head', 'head-sha', '--bench-rev', 'bench-sha')
    assert status.success?, stderr
    assert_includes stdout, 'Base: `base-sha` → PR: `head-sha`'
    assert_includes stdout, '| fib | 100 | 90 | -10.00% |'
  end

  def test_cli_requires_revision_options
    _, stderr, status = Open3.capture3(RbConfig.ruby, File.join(__dir__, 'zjit_callgrind.rb'), @directory)
    refute status.success?
    assert_includes stderr, '--base'
  end
end
