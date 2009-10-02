# Common setup for all test files.

# require 'flexmock/test_unit'

module TestMethods
  def assert_exception(ex, msg=nil, &block)
    assert_raise(ex, msg, &block)
  end
end
