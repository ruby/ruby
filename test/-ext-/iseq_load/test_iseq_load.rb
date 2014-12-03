require 'test/unit'

class TestIseqLoad < Test::Unit::TestCase
  require '-test-/iseq_load/iseq_load'
  ISeq = RubyVM::InstructionSequence

  def test_bug8543
    assert_iseq_roundtrip <<-'end;'
      puts "tralivali"
      def funct(a, b)
        a**b
      end
      3.times { |i| puts "Hello, world#{funct(2,i)}!" }
    end;
  end

  def test_case_when
    assert_iseq_roundtrip <<-'end;'
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
    assert_iseq_roundtrip('def splatsplat(**); end')
  end

  def test_hidden
    assert_iseq_roundtrip('def x(a, (b, *c), d: false); end')
  end

  def assert_iseq_roundtrip(src)
    a = ISeq.compile(src).to_a
    b = ISeq.iseq_load(a).to_a
    warn diff(a, b) if a != b
    assert_equal a, b
    assert_equal a, ISeq.iseq_load(b).to_a
  end

  def test_next_in_block_in_block
    skip "failing due to stack_max mismatch"
    assert_iseq_roundtrip <<-'end;'
      3.times { 3.times { next } }
    end;
  end

  def test_break_ensure
    skip "failing due to exception entry sp mismatch"
    assert_iseq_roundtrip <<-'end;'
      def m
        bad = true
        while true
          begin
            break
          ensure
            bad = false
          end
        end
      end
    end;
  end

  # FIXME: still failing
  def test_require_integration
    skip "iseq loader require integration tests still failing"
    f = File.expand_path(__FILE__)
    # $(top_srcdir)/test/ruby/test_....rb
    3.times { f = File.dirname(f) }
    Dir[File.join(f, 'ruby', '*.rb')].each do |f|
      iseq = ISeq.compile_file(f)
      orig = iseq.to_a.freeze

      loaded = ISeq.iseq_load(orig).to_a
      if loaded != orig
        warn f
        warn diff(orig, loaded)
      end
      #assert_equal orig, loaded
    end
  end
end
