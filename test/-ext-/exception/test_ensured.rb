# frozen_string_literal: false
require 'test/unit'

module Bug
  class Bug7802 < RuntimeError
  end

  class Test_ExceptionE < Test::Unit::TestCase
    def test_ensured
      assert_separately([], <<-'end;') # do

        require '-test-/exception'

        module Bug
          class Bug7802 < RuntimeError
            def try_method
              raise self
            end

            def ensured_method
              [1].detect {|i| true}
            end
          end
        end

        assert_raise(Bug::Bug7802, '[ruby-core:52022] [Bug #7802]') {
          Bug::Exception.ensured(Bug::Bug7802.new)
        }
      end;
    end
  end
end
