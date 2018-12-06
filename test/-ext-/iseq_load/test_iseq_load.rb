# frozen_string_literal: false
require 'test/unit'

class TestIseqLoad < Test::Unit::TestCase
  require '-test-/iseq_load'
  ISeq = RubyVM::InstructionSequence

  def test_bug8543
    assert_iseq_roundtrip "#{<<~"begin;"}\n#{<<~'end;'}"
    begin;
      puts "tralivali"
      def funct(a, b)
        a**b
      end
      3.times { |i| puts "Hello, world#{funct(2,i)}!" }
    end;
  end

  def test_stressful_roundtrip
    assert_separately(%w[-r-test-/iseq_load], "#{<<~"begin;"}\n#{<<~'end;;'}", timeout: 30)
    begin;
      ISeq = RubyVM::InstructionSequence
      def assert_iseq_roundtrip(src, line=caller_locations(1,1)[0].lineno+1)
        a = ISeq.compile(src, __FILE__, __FILE__, line).to_a
        b = ISeq.iseq_load(a).to_a
        assert_equal a, b, proc {diff(a, b)}
        b = ISeq.iseq_load(b).to_a
        assert_equal a, b, proc {diff(a, b)}
      end
      def test_bug8543
        assert_iseq_roundtrip "#{<<~"begin;"}\n#{<<~'end;'}"
        begin;
          puts "tralivali"
          def funct(a, b)
            a**b
          end
          3.times { |i| puts "Hello, world#{funct(2,i)}!" }
        end;
      end
      GC.stress = true
      test_bug8543
    end;;
  end

  def test_case_when
    assert_iseq_roundtrip "#{<<~"begin;"}\n#{<<~'end;'}"
    begin;
      def user_mask(target)
        target.each_char.inject(0) do |mask, chr|
          case chr
          when "u"
            mask | 04700
          when "g"
            mask | 02070
          when "o"
            mask | 01007
          when "a"
            mask | 07777
          else
            raise ArgumentError, "invalid `who' symbol in file mode: #{chr}"
          end
        end
      end
    end;
  end

  def test_splatsplat
    assert_iseq_roundtrip("#{<<-"begin;"}\n#{<<-'end;'}")
    begin;
      def splatsplat(**); end
    end;
  end

  def test_hidden
    assert_iseq_roundtrip("#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      def x(a, (b, *c), d: false); end
    end;
  end

  def assert_iseq_roundtrip(src, line=caller_locations(1,1)[0].lineno+1)
    a = ISeq.compile(src, __FILE__, __FILE__, line).to_a
    b = ISeq.iseq_load(a).to_a
    assert_equal a, b, proc {diff(a, b)}
    b = ISeq.iseq_load(b).to_a
    assert_equal a, b, proc {diff(a, b)}
  end

  def test_next_in_block_in_block
    @next_broke = false
    src, line = "#{<<~"begin;"}#{<<~'end;'}", __LINE__+2
    begin;
      3.times { 3.times { next; @next_broke = true } }
    end;
    a = ISeq.compile(src, __FILE__, __FILE__, line).to_a
    iseq = ISeq.iseq_load(a)
    iseq.eval
    assert_equal false, @next_broke
    skip "failing due to stack_max mismatch"
    assert_iseq_roundtrip(src)
  end

  def test_break_ensure
    src, line = "#{<<~"begin;"}#{<<~'end;'}", __LINE__+2
    begin;
      def test_break_ensure_def_method
        bad = true
        while true
          begin
            break
          ensure
            bad = false
          end
        end
        bad
      end
    end;
    a = ISeq.compile(src, __FILE__, __FILE__, line).to_a
    iseq = ISeq.iseq_load(a)
    iseq.eval
    assert_equal false, test_break_ensure_def_method
    skip "failing due to exception entry sp mismatch"
    assert_iseq_roundtrip(src)
  end

  def test_kwarg
    assert_iseq_roundtrip "#{<<~"begin;"}\n#{<<~'end;'}"
    begin;
      def foo(kwarg: :foo)
        kwarg
      end
      foo(kwarg: :bar)
    end;
  end

  # FIXME: still failing
  def test_require_integration
    skip "iseq loader require integration tests still failing"
    f = File.expand_path(__FILE__)
    # $(top_srcdir)/test/ruby/test_....rb
    3.times { f = File.dirname(f) }
    all_assertions do |all|
      Dir[File.join(f, 'ruby', '*.rb')].each do |f|
        all.for(f) do
          iseq = ISeq.compile_file(f)
          orig = iseq.to_a.freeze

          loaded = ISeq.iseq_load(orig).to_a
          assert loaded == orig, proc {"ISeq unmatch:\n"+diff(orig, loaded)}
        end
      end
    end
  end
end
