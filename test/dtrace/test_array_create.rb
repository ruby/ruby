require_relative 'helper'

module DTrace
  class TestArrayCreate < TestCase
    def test_lit
      trap_probe(probe, '[]') { |_,rbfile,saw|
        saw = saw.map(&:split).find_all { |num, file, line|
          file == rbfile && num == '0'
        }
        assert_equal([rbfile], saw.map { |line| line[1] })
        assert_equal(['1'], saw.map { |line| line[2] })
      }
    end

    def test_many_lit
      trap_probe(probe, '[1,2,3,4]') { |_,rbfile,saw|
        saw = saw.map(&:split).find_all { |num, file, line|
          file == rbfile && num == '4' && line == '1'
        }
        assert_operator saw.length, :>, 0
      }
    end

    private
    def probe type = 'array'
      <<-eoprobe
ruby$target:::#{type}-create
/arg1/
{
  printf("%d %s %d\\n", arg0, copyinstr(arg1), arg2);
}
      eoprobe
    end
  end
end if defined?(DTrace::TestCase)
