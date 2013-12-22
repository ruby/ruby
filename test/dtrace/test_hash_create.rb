require_relative 'helper'

module DTrace
  class TestHashCreate < TestCase
    def test_hash_new
      trap_probe(probe, 'Hash.new') { |_,rbfile,saw|
        saw = saw.map(&:split).find_all { |num, file, line|
          file == rbfile && num == '0'
        }
        assert_operator saw.length, :>, 0
      }
    end

    def test_hash_lit
      trap_probe(probe, '{}') { |_,rbfile,saw|
        saw = saw.map(&:split).find_all { |num, file, line|
          file == rbfile && num == '0'
        }
        assert_operator saw.length, :>, 0
      }
    end

    def test_hash_lit_elements
      trap_probe(probe, '{ :foo => :bar }') { |_,rbfile,saw|
        saw = saw.map(&:split).find_all { |num, file, line|
          file == rbfile && num == '2'
        }
        assert_operator saw.length, :>, 0
      }
    end

    def test_hash_lit_elements_string
      trap_probe(probe, '{ :foo => :bar, :bar => "baz" }') { |_,rbfile,saw|
        saw = saw.map(&:split).find_all { |num, file, line|
          file == rbfile && num == '4'
        }
        assert_operator saw.length, :>, 0
      }
    end

    private
    def probe
      <<-eoprobe
ruby$target:::hash-create
/arg1/
{
  printf("%d %s %d\\n", arg0, copyinstr(arg1), arg2);
}
      eoprobe
    end
  end
end if defined?(DTrace::TestCase)
