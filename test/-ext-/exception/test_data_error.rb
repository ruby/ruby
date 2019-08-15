# frozen_string_literal: false
require 'test/unit'

module Bug
  class Test_ExceptionDE < Test::Unit::TestCase
    def test_cleanup_data_error
      bug9167 = '[ruby-core:58643] [Bug #9167]'
      assert_normal_exit(<<-'end;', bug9167) # do
        require '-test-/exception'
        raise Bug::Exception::DataError, "Error"
      end;
    end
  end
end
