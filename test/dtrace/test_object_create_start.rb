require 'dtrace/helper'

module DTrace
  class TestObjectCreateStart < TestCase
    def test_object_create_start
      trap_probe(probe, '10.times { Object.new }') { |_,rbfile,saw|
        saw = saw.map(&:split).find_all { |_, file, _|
          file == rbfile
        }
        assert_equal 10, saw.length
      }
    end

    def test_object_create_start_name
      trap_probe(probe, 'Hash.new') { |_,rbfile,saw|
        saw = saw.map(&:split).find_all { |klass, file, line|
          file == rbfile
        }
        assert_equal(%w{ Hash }, saw.map(&:first))
        assert_equal([rbfile], saw.map { |line| line[1] })
        assert_equal(['1'], saw.map { |line| line[2] })
      }
    end

    private
    def probe
      <<-eoprobe
ruby$target:::object-create
{
  printf("%s %s %d\\n", copyinstr(arg0), copyinstr(arg1), arg2);
}
      eoprobe
    end
  end
end if defined?(DTrace::TestCase)
