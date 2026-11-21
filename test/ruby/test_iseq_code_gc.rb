# frozen_string_literal: false
require 'test/unit'
require 'tmpdir'

# The executable parts of an iseq with child iseqs live in a separate
# code object that is only kept alive by things that can run the code
# (frames, method entries, procs, iseq wrappers, backtraces). A retained
# Proc created in a class body keeps the class body's metadata but no
# longer pins the class body's code or its sibling blocks.
class TestISeqCodeGC < Test::Unit::TestCase
  LIB = <<~'RUBY'
    LOCS = []
    module CodeGCA
      LOCS << caller_locations(0, 1).first
      class Inner
        y = 42
        LOCS << caller_locations(0, 1).first
        begin
          raise "boom"
        rescue => e
          ERR = e
        end
        begin
          nil.foo
        rescue NoMethodError => e
          NME = e
        end
        KEEP = proc { |a| [y, a, binding.local_variables.sort, eval("y + 1")] }
        BIND = binding
        def hello(n) = "hello #{n}"
        class << self
          def sing = :sing
        end
      end
    end
  RUBY

  def with_lib(code, extra = nil)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "code_gc_lib.rb"), LIB)
      File.write(File.join(dir, "code_gc_many.rb"), extra) if extra
      assert_separately(["-I", dir], <<~PRE + code)
        $code_gc_dir = #{dir.dump}
        require "objspace"
        require "error_highlight"
        def settle = 4.times { GC.start; sleep 0.01 }
        def counts
          settle
          c = ObjectSpace.count_imemo_objects
          [c[:imemo_iseq].to_i, c[:imemo_iseq_code].to_i]
        end
      PRE
    end
  end

  def test_retained_proc_does_not_pin_siblings
    many = +"class CodeGCMany\n"
    400.times { |i| many << "  [1, 2].each { |x| x + #{i} }\n" }
    many << "  KEEP = proc { 1 }\n  def m = 2\nend\n"
    with_lib(<<~'RUBY', many)
      before = counts
      require "code_gc_many"
      after = counts
      assert_operator after[0] - before[0], :<=, 10, "retained iseqs"
      assert_operator after[1] - before[1], :<=, 2, "retained code objects"
      assert_equal 1, CodeGCMany::KEEP.call
      assert_equal 2, CodeGCMany.new.m
      GC.verify_internal_consistency
    RUBY
  end

  def test_wrapper_keeps_code
    with_lib(<<~'RUBY')
      top = nil
      TracePoint.new(:script_compiled) { |t| top ||= t.instruction_sequence if t.instruction_sequence&.path&.end_with?("code_gc_lib.rb") }.enable { require "code_gc_lib" }
      settle
      all = []
      walk = ->(i) { i.each_child { |c| all << c; walk.(c) } }
      walk.(top)
      assert_operator all.size, :>=, 6
      all.each { |c| assert_kind_of String, c.disasm; assert_kind_of Array, c.to_a }
      assert_include top.disasm, "defineclass"
      assert_equal top.disasm, RubyVM::InstructionSequence.load_from_binary(top.to_binary).disasm
      assert_not_empty top.trace_points
      v, $VERBOSE = $VERBOSE, nil
      top.eval
      $VERBOSE = v
      assert_equal 42, CodeGCA::Inner::KEEP.call(1)[0]
    RUBY
  end

  def test_metadata_and_captured_code_survive
    with_lib(<<~'RUBY')
      require "code_gc_lib"
      settle
      assert_equal [3, 6], LOCS.map(&:lineno)
      assert_equal 8, CodeGCA::Inner::ERR.backtrace_locations[0].lineno
      assert_include CodeGCA::Inner::NME.detailed_message(highlight: false), "^^^^"
      assert_equal [42, 5, [:a, :e, :y], 43], CodeGCA::Inner::KEEP.call(5)
      assert_equal 84, CodeGCA::Inner::BIND.eval("y * 2")
      assert_equal 42, CodeGCA::Inner::BIND.local_variable_get(:y)
      assert_equal "hello 1", CodeGCA::Inner.new.hello(1)
      assert_equal :sing, CodeGCA::Inner.sing
      events = []
      TracePoint.new(:b_call) { |t| events << t.event }.enable { CodeGCA::Inner::KEEP.call(1) }
      assert_include events, :b_call
      if GC.respond_to?(:compact)
        GC.verify_compaction_references(expand_heap: true, toward: :empty)
        assert_equal 6, LOCS[1].lineno
        assert_equal 7, CodeGCA::Inner::KEEP.call(7)[1]
        assert_include CodeGCA::Inner::NME.detailed_message(highlight: false), "^^^^"
      end
      GC.verify_internal_consistency
    RUBY
  end

  def test_ractors_run_code_from_same_file
    with_lib(<<~'RUBY')
      File.write(File.join($code_gc_dir, "code_gc_r.rb"), <<~R)
        class CodeGCR
          KEEP = Ractor.make_shareable(proc { 21 * 2 })
          def self.v = 7
          20.times { }
        end
      R
      rs = 4.times.map { Ractor.new { require "code_gc_r"; 200.times.sum { CodeGCR.v + CodeGCR::KEEP.call } } }
      assert_equal [9800], rs.map(&:value).uniq
      settle
      GC.verify_internal_consistency
    RUBY
  end

  def test_callcc_reenters_finished_class_body
    with_lib(<<~'RUBY')
      v, $VERBOSE = $VERBOSE, nil
      require "continuation"
      $VERBOSE = v
      $k = nil; $n = 0
      File.write(File.join($code_gc_dir, "code_gc_cc.rb"), "class CodeGCCC\n  callcc { |k| $k = k }\n  $n += 1\n  KEEP = proc {} if $n == 1\nend\n")
      require "code_gc_cc"
      settle
      $k.call if $n < 3
      assert_equal 3, $n
    RUBY
  end

  def test_gc_stress
    with_lib(<<~'RUBY')
      GC.stress = true
      eval("class CodeGCStress; P = proc { [1].map { _1 + 1 } }; def m = P.call; end")
      GC.stress = false
      assert_equal [2], CodeGCStress.new.m
    RUBY
  end
end
