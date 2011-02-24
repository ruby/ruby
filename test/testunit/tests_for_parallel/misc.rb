# FIXME: more portability code
if caller(7) && /block in non_options/ =~ caller(7)[0]
  class TestCaseForParallelTest < Test::Unit::TestCase;end
else
  module Test
    module Unit
      class Worker
        def run_tests
          _run_anything :ptest
        end
      end
      class Runner
        def run_tests
          _run_anything :ptest
        end
      end
    end
  end
  module MiniTest
    class Unit
      class << TestCase
        alias ptest_suites test_suites
        def ptest_methods;[];end
      end
    end
  end

  class TestCaseForParallelTest < Test::Unit::TestCase
    class << self
      undef ptest_methods
      def ptest_methods
        public_instance_methods(true).grep(/^ptest/).map { |m| m.to_s }
      end
    end
  end
end
