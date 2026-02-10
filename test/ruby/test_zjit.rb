# frozen_string_literal: true
#
# This set of tests can be run with:
# make test-all TESTS=test/ruby/test_zjit.rb

require 'test/unit'
require 'envutil'
require_relative '../lib/jit_support'
return unless JITSupport.zjit_supported?

class TestZJIT < Test::Unit::TestCase
  def test_enabled
    assert_runs 'false', <<~RUBY, zjit: false
      RubyVM::ZJIT.enabled?
    RUBY
    assert_runs 'true', <<~RUBY, zjit: true
      RubyVM::ZJIT.enabled?
    RUBY
  end

  def test_stats_enabled
    assert_runs 'false', <<~RUBY, stats: false
      RubyVM::ZJIT.stats_enabled?
    RUBY
    assert_runs 'true', <<~RUBY, stats: true
      RubyVM::ZJIT.stats_enabled?
    RUBY
  end

  def test_stats_string_no_zjit
    assert_runs 'nil', <<~RUBY, zjit: false
      RubyVM::ZJIT.stats_string
    RUBY
    assert_runs 'true', <<~RUBY, stats: false
      RubyVM::ZJIT.stats_string.is_a?(String)
    RUBY
    assert_runs 'true', <<~RUBY, stats: true
      RubyVM::ZJIT.stats_string.is_a?(String)
    RUBY
  end

  def test_stats_quiet
    # Test that --zjit-stats-quiet collects stats but doesn't print them
    script = <<~RUBY
      def test = 42
      test
      test
      puts RubyVM::ZJIT.stats_enabled?
    RUBY

    stats_header = "***ZJIT: Printing ZJIT statistics on exit***"

    # With --zjit-stats, stats should be printed to stderr
    out, err, status = eval_with_jit(script, stats: true)
    assert_success(out, err, status)
    assert_includes(err, stats_header)
    assert_equal("true\n", out)

    # With --zjit-stats-quiet, stats should NOT be printed but still enabled
    out, err, status = eval_with_jit(script, stats: :quiet)
    assert_success(out, err, status)
    refute_includes(err, stats_header)
    assert_equal("true\n", out)

    # With --zjit-stats=<path>, stats should be printed to the path
    Tempfile.create("zjit-stats-") {|tmp|
      stats_file = tmp.path
      tmp.puts("Lorem ipsum dolor sit amet, consectetur adipiscing elit, ...")
      tmp.close

      out, err, status = eval_with_jit(script, stats: stats_file)
      assert_success(out, err, status)
      refute_includes(err, stats_header)
      assert_equal("true\n", out)
      assert_equal stats_header, File.open(stats_file) {|f| f.gets(chomp: true)}, "should be overwritten"
    }
  end

  def test_enable_through_env
    child_env = {'RUBY_YJIT_ENABLE' => nil, 'RUBY_ZJIT_ENABLE' => '1'}
    assert_in_out_err([child_env, '-v'], '') do |stdout, stderr|
      assert_includes(stdout.first, '+ZJIT')
      assert_equal([], stderr)
    end
  end

  def test_zjit_enable
    # --disable-all is important in case the build/environment has YJIT enabled by
    # default through e.g. -DYJIT_FORCE_ENABLE. Can't enable ZJIT when YJIT is on.
    assert_separately(["--disable-all"], <<~'RUBY')
      refute_predicate RubyVM::ZJIT, :enabled?
      refute_predicate RubyVM::ZJIT, :stats_enabled?
      refute_includes RUBY_DESCRIPTION, "+ZJIT"

      RubyVM::ZJIT.enable

      assert_predicate RubyVM::ZJIT, :enabled?
      refute_predicate RubyVM::ZJIT, :stats_enabled?
      assert_includes RUBY_DESCRIPTION, "+ZJIT"
    RUBY
  end

  def test_zjit_disable
    assert_separately(["--zjit", "--zjit-disable"], <<~'RUBY')
      refute_predicate RubyVM::ZJIT, :enabled?
      refute_includes RUBY_DESCRIPTION, "+ZJIT"

      RubyVM::ZJIT.enable

      assert_predicate RubyVM::ZJIT, :enabled?
      assert_includes RUBY_DESCRIPTION, "+ZJIT"
    RUBY
  end

  def test_zjit_enable_respects_existing_options
    assert_separately(['--zjit-disable', '--zjit-stats-quiet'], <<~RUBY)
      refute_predicate RubyVM::ZJIT, :enabled?
      assert_predicate RubyVM::ZJIT, :stats_enabled?

      RubyVM::ZJIT.enable

      assert_predicate RubyVM::ZJIT, :enabled?
      assert_predicate RubyVM::ZJIT, :stats_enabled?
    RUBY
  end

  def test_toplevel_binding
    # Not using assert_compiles, which doesn't use the toplevel frame for `test_script`.
    out, err, status = eval_with_jit(%q{
      a = 1
      b = 2
      TOPLEVEL_BINDING.local_variable_set(:b, 3)
      c = 4
      print [a, b, c]
    })
    assert_success(out, err, status)
    assert_equal "[1, 3, 4]", out
  end

  def test_send_exit_with_uninitialized_locals
    assert_runs 'nil', %q{
      def entry(init)
        function_stub_exit(init)
      end

      def function_stub_exit(init)
        uninitialized_local = 1 if init
        uninitialized_local
      end

      entry(true) # profile and set 1 to the local slot
      entry(false)
    }, call_threshold: 2, allowed_iseqs: 'entry@-e:2'
  end

  def test_opt_new_with_custom_allocator
    assert_compiles '"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"', %q{
      require "digest"
      def test = Digest::SHA256.new.hexdigest
      test; test
    }, insns: [:opt_new], call_threshold: 2
  end

  def test_opt_new_with_custom_allocator_raises
    assert_compiles '[42, 42]', %q{
      require "digest"
      class C < Digest::Base; end
      def test
        begin
          Digest::Base.new
        rescue NotImplementedError
          42
        end
      end
      [test, test]
    }, insns: [:opt_new], call_threshold: 2
  end

  def test_uncached_getconstant_path
    assert_compiles RUBY_COPYRIGHT.dump, %q{
      def test = RUBY_COPYRIGHT
      test
    }, call_threshold: 1, insns: [:opt_getconstant_path]
  end

  def test_getconstant_path_autoload
    # A constant-referencing expression can run arbitrary code through Kernel#autoload.
    Dir.mktmpdir('autoload') do |tmpdir|
      autoload_path = File.join(tmpdir, 'test_getconstant_path_autoload.rb')
      File.write(autoload_path, 'X = RUBY_COPYRIGHT')

      assert_compiles RUBY_COPYRIGHT.dump, %Q{
        Object.autoload(:X, #{File.realpath(autoload_path).inspect})
        def test = X
        test
      }, call_threshold: 1, insns: [:opt_getconstant_path]
    end
  end

  def test_send_backtrace
    backtrace = [
      "-e:2:in 'Object#jit_frame1'",
      "-e:3:in 'Object#entry'",
      "-e:5:in 'block in <main>'",
      "-e:6:in '<main>'",
    ]
    assert_compiles backtrace.inspect, %q{
      def jit_frame2 = caller     # 1
      def jit_frame1 = jit_frame2 # 2
      def entry = jit_frame1      # 3
      entry # profile send        # 4
      entry                       # 5
    }, call_threshold: 2
  end

  # tool/ruby_vm/views/*.erb relies on the zjit instructions a) being contiguous and
  # b) being reliably ordered after all the other instructions.
  def test_instruction_order
    insn_names = RubyVM::INSTRUCTION_NAMES
    zjit, others = insn_names.map.with_index.partition { |name, _| name.start_with?('zjit_') }
    zjit_indexes = zjit.map(&:last)
    other_indexes = others.map(&:last)
    zjit_indexes.product(other_indexes).each do |zjit_index, other_index|
      assert zjit_index > other_index, "'#{insn_names[zjit_index]}' at #{zjit_index} "\
        "must be defined after '#{insn_names[other_index]}' at #{other_index}"
    end
  end

  def test_require_rubygems
    assert_runs 'true', %q{
      require 'rubygems'
    }, call_threshold: 2
  end

  def test_require_rubygems_with_auto_compact
    omit("GC.auto_compact= support is required for this test") unless GC.respond_to?(:auto_compact=)
    assert_runs 'true', %q{
      GC.auto_compact = true
      require 'rubygems'
    }, call_threshold: 2
  end

  def test_stats_availability
    assert_runs '[true, true]', %q{
      def test = 1
      test
      [
        RubyVM::ZJIT.stats[:zjit_insn_count] > 0,
        RubyVM::ZJIT.stats(:zjit_insn_count) > 0,
      ]
    }, stats: true
  end

  def test_stats_consistency
    assert_runs '[]', %q{
      def test = 1
      test # increment some counters

      RubyVM::ZJIT.stats.to_a.filter_map do |key, value|
        # The value may be incremented, but the class should stay the same
        other_value = RubyVM::ZJIT.stats(key)
        if value.class != other_value.class
          [key, value, other_value]
        end
      end
    }, stats: true
  end

  def test_reset_stats
    assert_runs 'true', %q{
      def test = 1
      100.times { test }

      # Get initial stats and verify they're non-zero
      initial_stats = RubyVM::ZJIT.stats

      # Reset the stats
      RubyVM::ZJIT.reset_stats!

      # Get stats after reset
      reset_stats = RubyVM::ZJIT.stats

      [
        # After reset, counters should be zero or at least much smaller
        # (some instructions might execute between reset and reading stats)
        :zjit_insn_count.then { |s| initial_stats[s] > 0 && reset_stats[s] < initial_stats[s] },
        :compiled_iseq_count.then { |s| initial_stats[s] > 0 && reset_stats[s] < initial_stats[s] }
      ].all?
    }, stats: true
  end

  def test_zjit_option_uses_array_each_in_ruby
    omit 'ZJIT wrongly compiles Array#each, so it is disabled for now'
    assert_runs '"<internal:array>"', %q{
      Array.instance_method(:each).source_location&.first
    }
  end

  def test_line_tracepoint_on_c_method
    assert_compiles '"[[:line, true]]"', %q{
      events = []
      events.instance_variable_set(
        :@tp,
        TracePoint.new(:line) { |tp| events << [tp.event, tp.lineno] if tp.path == __FILE__ }
      )
      def events.to_str
        @tp.enable; ''
      end

      # Stay in generated code while enabling tracing
      def events.compiled(obj)
        String(obj)
        @tp.disable; __LINE__
      end

      line = events.compiled(events)
      events[0][-1] = (events[0][-1] == line)

      events.to_s # can't dump events as it's a singleton object AND it has a TracePoint instance variable, which also can't be dumped
    }
  end

  def test_targeted_line_tracepoint_in_c_method_call
    assert_compiles '"[true]"', %q{
      events = []
      events.instance_variable_set(:@tp, TracePoint.new(:line) { |tp| events << tp.lineno })
      def events.to_str
        @tp.enable(target: method(:compiled))
        ''
      end

      # Stay in generated code while enabling tracing
      def events.compiled(obj)
        String(obj)
        __LINE__
      end

      line = events.compiled(events)
      events[0] = (events[0] == line)

      events.to_s # can't dump events as it's a singleton object AND it has a TracePoint instance variable, which also can't be dumped
    }
  end

  def test_regression_cfp_sp_set_correctly_before_leaf_gc_call
    assert_compiles ':ok', %q{
      def check(l, r)
        return 1 unless l
        1 + check(*l) + check(*r)
      end

      def tree(depth)
        # This duparray is our leaf-gc target.
        return [nil, nil] unless depth > 0

        # Modify the local and pass it to the following calls.
        depth -= 1
        [tree(depth), tree(depth)]
      end

      def test
        GC.stress = true
        2.times do
          t = tree(11)
          check(*t)
        end
        :ok
      end

      test
    }, call_threshold: 14, num_profiles: 5
  end

  def test_exit_tracing
    # This is a very basic smoke test. The StackProf format
    # this option generates is external to us.
    Dir.mktmpdir("zjit_test_exit_tracing") do |tmp_dir|
      assert_compiles('true', <<~RUBY, extra_args: ['-C', tmp_dir, '--zjit-trace-exits'])
        def test(object) = object.itself

        # induce an exit just for good measure
        array = []
        test(array)
        test(array)
        def array.itself = :not_itself
        test(array)

        RubyVM::ZJIT.exit_locations.is_a?(Hash)
      RUBY
      dump_files = Dir.glob('zjit_exits_*.dump', base: tmp_dir)
      assert_equal(1, dump_files.length)
      refute(File.empty?(File.join(tmp_dir, dump_files.first)))
    end
  end

  private

  # Assert that every method call in `test_script` can be compiled by ZJIT
  # at a given call_threshold
  def assert_compiles(expected, test_script, insns: [], **opts)
    assert_runs(expected, test_script, insns:, assert_compiles: true, **opts)
  end

  # Assert that `test_script` runs successfully with ZJIT enabled.
  # Unlike `assert_compiles`, `assert_runs(assert_compiles: false)`
  # allows ZJIT to skip compiling methods.
  def assert_runs(expected, test_script, insns: [], assert_compiles: false, **opts)
    pipe_fd = 3
    disasm_method = :test

    script = <<~RUBY
      ret_val = (_test_proc = -> { #{('RubyVM::ZJIT.assert_compiles; ' if assert_compiles)}#{test_script.lstrip} }).call
      result = {
        ret_val:,
        #{ unless insns.empty?
           "insns: RubyVM::InstructionSequence.of(method(#{disasm_method.inspect})).to_a"
        end}
      }
      IO.open(#{pipe_fd}).write(Marshal.dump(result))
    RUBY

    out, err, status, result = eval_with_jit(script, pipe_fd:, **opts)
    assert_success(out, err, status)

    result = Marshal.load(result)
    assert_equal(expected, result.fetch(:ret_val).inspect)

    unless insns.empty?
      iseq = result.fetch(:insns)
      assert_equal(
        "YARVInstructionSequence/SimpleDataFormat",
        iseq.first,
        "Failed to get ISEQ disassembly. " \
        "Make sure to put code directly under the '#{disasm_method}' method."
      )
      iseq_insns = iseq.last

      expected_insns = Set.new(insns)
      iseq_insns.each do
        next unless it.is_a?(Array)
        expected_insns.delete(it.first)
      end
      assert(expected_insns.empty?, -> { "Not present in ISeq: #{expected_insns.to_a}" })
    end
  end

  # Run a Ruby process with ZJIT options and a pipe for writing test results
  def eval_with_jit(
    script,
    call_threshold: 1,
    num_profiles: 1,
    zjit: true,
    stats: false,
    debug: true,
    allowed_iseqs: nil,
    extra_args: nil,
    timeout: 1000,
    pipe_fd: nil
  )
    args = ["--disable-gems", *extra_args]
    if zjit
      args << "--zjit-call-threshold=#{call_threshold}"
      args << "--zjit-num-profiles=#{num_profiles}"
      case stats
      when true
        args << "--zjit-stats"
      when :quiet
        args << "--zjit-stats-quiet"
      else
        args << "--zjit-stats=#{stats}" if stats
      end
      args << "--zjit-debug" if debug
      if allowed_iseqs
        jitlist = Tempfile.new("jitlist")
        jitlist.write(allowed_iseqs)
        jitlist.close
        args << "--zjit-allowed-iseqs=#{jitlist.path}"
      end
    end
    args << "-e" << script_shell_encode(script)
    ios = {}
    if pipe_fd
      pipe_r, pipe_w = IO.pipe
      # Separate thread so we don't deadlock when
      # the child ruby blocks writing the output to pipe_fd
      pipe_out = nil
      pipe_reader = Thread.new do
        pipe_out = pipe_r.read
        pipe_r.close
      end
      ios[pipe_fd] = pipe_w
    end
    result = EnvUtil.invoke_ruby(args, '', true, true, rubybin: RbConfig.ruby, timeout: timeout, ios:)
    if pipe_fd
      pipe_w.close
      pipe_reader.join(timeout)
      result << pipe_out
    end
    result
  ensure
    pipe_reader&.kill
    pipe_reader&.join(timeout)
    pipe_r&.close
    pipe_w&.close
    jitlist&.unlink
  end

  def assert_success(out, err, status)
    message = "exited with status #{status.to_i}"
    message << "\nstdout:\n```\n#{out}```\n" unless out.empty?
    message << "\nstderr:\n```\n#{err}```\n" unless err.empty?
    assert status.success?, message
  end

  def script_shell_encode(s)
    # We can't pass utf-8-encoded characters directly in a shell arg. But we can use Ruby \u constants.
    s.chars.map { |c| c.ascii_only? ? c : "\\u%x" % c.codepoints[0] }.join
  end
end
