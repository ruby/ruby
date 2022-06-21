# frozen_string_literal: true
require 'test/unit'
require 'tmpdir'
require_relative '../lib/jit_support'

# Test for --mjit option
class TestMJIT < Test::Unit::TestCase
  include JITSupport

  IGNORABLE_PATTERNS = [
    /\AJIT recompile: .+\n\z/,
    /\AJIT inline: .+\n\z/,
    /\AJIT cancel: .+\n\z/,
    /\ASuccessful MJIT finish\n\z/,
  ]
  MAX_CACHE_PATTERNS = [
    /\AJIT compaction \([^)]+\): .+\n\z/,
    /\AToo many JIT code, but skipped unloading units for JIT compaction\n\z/,
    /\ANo units can be unloaded -- .+\n\z/,
  ]

  # trace_* insns are not compiled for now...
  TEST_PENDING_INSNS = RubyVM::INSTRUCTION_NAMES.select { |n| n.start_with?('trace_') }.map(&:to_sym) + [
    # not supported yet
    :defineclass,

    # to be tested
    :invokebuiltin,

    # never used
    :opt_invokebuiltin_delegate,
  ].each do |insn|
    if !RubyVM::INSTRUCTION_NAMES.include?(insn.to_s)
      warn "instruction #{insn.inspect} is not defined but included in TestMJIT::TEST_PENDING_INSNS"
    end
  end

  def self.untested_insns
    @untested_insns ||= (RubyVM::INSTRUCTION_NAMES.map(&:to_sym) - TEST_PENDING_INSNS)
  end

  def self.setup
    return if defined?(@setup_hooked)
    @setup_hooked = true

    # ci.rvm.jp caches its build environment. Clean up temporary files left by SEGV.
    if ENV['RUBY_DEBUG']&.include?('ci')
      Dir.glob("#{ENV.fetch('TMPDIR', '/tmp')}/_ruby_mjit_p*u*.*").each do |file|
        puts "test/ruby/test_mjit.rb: removing #{file}"
        File.unlink(file)
      end
    end

    # ruby -w -Itest/lib test/ruby/test_mjit.rb
    if $VERBOSE
      pid = $$
      at_exit do
        if pid == $$ && !TestMJIT.untested_insns.empty?
          warn "you may want to add tests for following insns, when you have a chance: #{TestMJIT.untested_insns.join(' ')}"
        end
      end
    end
  end

  def setup
    unless JITSupport.supported?
      omit 'JIT seems not supported on this platform'
    end
    self.class.setup
  end

  def test_compile_insn_nop
    assert_compile_once('nil rescue true', result_inspect: 'nil', insns: %i[nop])
  end

  private

  # The shortest way to test one proc
  def assert_compile_once(script, result_inspect:, insns: [], uplevel: 1)
    if script.match?(/\A\n.+\n\z/m)
      script = script.gsub(/^/, '  ')
    else
      script = " #{script} "
    end
    assert_eval_with_jit("p proc {#{script}}.call", stdout: "#{result_inspect}\n", success_count: 1, insns: insns, uplevel: uplevel + 1)
  end

  # Shorthand for normal test cases
  def assert_eval_with_jit(script, stdout: nil, success_count:, recompile_count: nil, min_calls: 1, max_cache: 1000, insns: [], uplevel: 1, ignorable_patterns: [])
    out, err = eval_with_jit(script, verbose: 1, min_calls: min_calls, max_cache: max_cache)
    puts "\n[stderr]==============\n#{err}======================\n"
    err.scan(/^#{JIT_SUCCESS_PREFIX}:.*$/).each do |line|
      file = line.split(" ").last
      puts "\n[#{file}]=====================\n#{File.read(file)}=======================\n\n"
    end
    success_actual = err.scan(/^#{JIT_SUCCESS_PREFIX}:/).size
    recompile_actual = err.scan(/^#{JIT_RECOMPILE_PREFIX}:/).size
    # Add --mjit-verbose=2 logs for cl.exe because compiler's error message is suppressed
    # for cl.exe with --mjit-verbose=1. See `start_process` in mjit_worker.c.
    if RUBY_PLATFORM.match?(/mswin/) && success_count != success_actual
      out2, err2 = eval_with_jit(script, verbose: 2, min_calls: min_calls, max_cache: max_cache)
    end

    # Make sure that the script has insns expected to be tested
    used_insns = method_insns(script)
    insns.each do |insn|
      mark_tested_insn(insn, used_insns: used_insns, uplevel: uplevel + 3)
    end

    suffix = "script:\n#{code_block(script)}\nstderr:\n#{code_block(err)}#{(
      "\nstdout(verbose=2 retry):\n#{code_block(out2)}\nstderr(verbose=2 retry):\n#{code_block(err2)}" if out2 || err2
    )}"
    assert_equal(
      success_count, success_actual,
      "Expected #{success_count} times of JIT success, but succeeded #{success_actual} times.\n\n#{suffix}",
    )
    if recompile_count
      assert_equal(
        recompile_count, recompile_actual,
        "Expected #{success_count} times of JIT recompile, but recompiled #{success_actual} times.\n\n#{suffix}",
      )
    end
    if stdout
      assert_equal(stdout, out, "Expected stdout #{out.inspect} to match #{stdout.inspect} with script:\n#{code_block(script)}")
    end
    err_lines = err.lines.reject! do |l|
      l.chomp.empty? || l.match?(/\A#{JIT_SUCCESS_PREFIX}/) || (IGNORABLE_PATTERNS + ignorable_patterns).any? { |pat| pat.match?(l) }
    end
    unless err_lines.empty?
      warn err_lines.join(''), uplevel: uplevel
    end
  end

  def mark_tested_insn(insn, used_insns:, uplevel: 1)
    # Currently, this check emits a false-positive warning against opt_regexpmatch2,
    # so the insn is excluded explicitly. See https://bugs.ruby-lang.org/issues/18269
    if !used_insns.include?(insn) && insn != :opt_regexpmatch2
      $stderr.puts
      warn "'#{insn}' insn is not included in the script. Actual insns are: #{used_insns.join(' ')}\n", uplevel: uplevel
    end
    TestMJIT.untested_insns.delete(insn)
  end

  # Collect block's insns or defined method's insns, which are expected to be JIT-ed.
  # Note that this intentionally excludes insns in script's toplevel because they are not JIT-ed.
  def method_insns(script)
    insns = []
    RubyVM::InstructionSequence.compile(script).to_a.last.each do |(insn, *args)|
      case insn
      when :send
        insns += collect_insns(args.last)
      when :definemethod, :definesmethod
        insns += collect_insns(args[1])
      when :defineclass
        insns += collect_insns(args[1])
      end
    end
    insns.uniq
  end

  # Recursively collect insns in iseq_array
  def collect_insns(iseq_array)
    return [] if iseq_array.nil?

    insns = iseq_array.last.select { |x| x.is_a?(Array) }.map(&:first)
    iseq_array.last.each do |(insn, *args)|
      case insn
      when :definemethod, :definesmethod, :send
        insns += collect_insns(args.last)
      end
    end
    insns
  end
end
