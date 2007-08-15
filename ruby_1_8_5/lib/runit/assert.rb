# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/assertions'
require 'runit/error'

module RUNIT
  module Assert
    include Test::Unit::Assertions

    def setup_assert
    end

    def assert_no_exception(*args, &block)
      assert_nothing_raised(*args, &block)
    end

    # To deal with the fact that RubyUnit does not check that the
    # regular expression is, indeed, a regular expression, if it is
    # not, we do our own assertion using the same semantics as
    # RubyUnit
    def assert_match(actual_string, expected_re, message="")
      _wrap_assertion {
        full_message = build_message(message, "Expected <?> to match <?>", actual_string, expected_re)
        assert_block(full_message) {
          expected_re =~ actual_string
        }
        Regexp.last_match
      }
    end

    def assert_not_nil(actual, message="")
      assert(!actual.nil?, message)
    end

    def assert_not_match(actual_string, expected_re, message="")
      assert_no_match(expected_re, actual_string, message)
    end

    def assert_matches(*args)
      assert_match(*args)
    end

    def assert_fail(message="")
      flunk(message)
    end

    def assert_equal_float(expected, actual, delta, message="")
      assert_in_delta(expected, actual, delta, message)
    end

    def assert_send(object, method, *args)
      super([object, method, *args])
    end

    def assert_exception(exception, message="", &block)
      assert_raises(exception, message, &block)
    end

    def assert_respond_to(method, object, message="")
      if (called_internally?)
        super
      else
        super(object, method, message)
      end
    end

    def called_internally?
      /assertions\.rb/.match(caller[1])
    end
  end
end
