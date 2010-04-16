# Author:: Masaki Suketa.
# Adapted by:: Nathaniel Talbott.
# Copyright:: Copyright (c) Masaki Suketa. All rights reserved.
# Copyright:: Copyright (c) 2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'rubyunit'

module RUNIT
  class TargetAssert
    include RUNIT::Assert
  end

  class TestAssert < RUNIT::TestCase
    def setup
      @assert = TargetAssert.new
      @e = nil
    end

    def test_assert
      sub_test_assert_pass(true)
      sub_test_assert_pass(TRUE)
      sub_test_assert_failure(false)
      sub_test_assert_failure(FALSE)
      sub_test_assert_failure(nil)
      sub_test_assert_pass("")
      sub_test_assert_pass("ok")
      sub_test_assert_pass(0)
      sub_test_assert_pass(1)
    end

    def test_assert_with_2_argument
      assert_no_exception {
        assert(true, "3")
      }
      assert_no_exception {
        assert(true)
      }
    end

    def test_assert_equal_float_0_1
      assert_proc = Proc.new {
        @assert.assert_equal_float(1.4, 1.35, 0.1)
      }
      sub_assert_pass(assert_proc)
    end

    def test_assert_equal_float_0_5
      assert_proc = Proc.new {
        @assert.assert_equal_float(1.4, 1.34, 0.5)
      }
      sub_assert_pass(assert_proc)
    end

    def test_assert_equal_float_0
      assert_proc = Proc.new {
        @assert.assert_equal_float(1.4, 1.4, 0)
      }
      sub_assert_pass(assert_proc)
    end

    def test_assert_equal_float_0_raise
      assert_proc = Proc.new {
        @assert.assert_equal_float(1.4, 1.34, 0)
      }
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_equal_float_0_01
      assert_proc = Proc.new {
        @assert.assert_equal_float(1.4, 1.35, 0.01)
      }
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_equal_float_0_001
      assert_proc = Proc.new {
        @assert.assert_equal_float(Math.sqrt(2), 1.414, 0.001)
      }
      sub_assert_pass(assert_proc)
    end

    def test_assert_equal_float_minus_1_0
      assert_proc = Proc.new {
        @assert.assert_equal_float(1.4, 1.35, -1.0)
      }
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_fail
      except = nil
      begin
        @assert.assert_fail("failure")
      rescue Exception
        except = $!
      end
      assert_not_nil(except)
    end

    def sub_test_assert_pass(obj)
      assert_proc = Proc.new {
        @assert.assert(obj)
      }
      sub_assert_pass(assert_proc)
    end

    def sub_test_assert_failure(obj)
      assert_proc = Proc.new {
        @assert.assert(obj)
      }
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_equal
      assert_proc = Proc.new {
        @assert.assert_equal(2, 2)
      }
      sub_assert_pass(assert_proc)
      assert_proc = Proc.new {
        @assert.assert_equal(2, 3)
      }
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_nil
      obj = nil
      assert_proc = Proc.new {
        @assert.assert_nil(obj)
      }
      sub_assert_pass(assert_proc)
      obj = 'string'
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_not_nil
      obj = 'string'
      assert_proc = Proc.new {
        @assert.assert_not_nil(obj)
      }
      sub_assert_pass(assert_proc)

      obj = nil
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_operator
      assert_proc = Proc.new {
        @assert.assert_operator(2, :<, 3)
      }
      sub_assert_pass(assert_proc)
      assert_proc = Proc.new {
        @assert.assert_operator(2, :>, 3)
      }
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_respond_to
      sub_test_assert_respond_to('string', 'sub', 'foo')
      sub_test_assert_respond_to('string', :sub, :foo)
    end

    def sub_test_assert_respond_to(obj, msg, dummy_msg)
      assert_proc = Proc.new {
        @assert.assert_respond_to(msg, obj)
      }
      sub_assert_pass(assert_proc)
      assert_proc = Proc.new {
        @assert.assert_respond_to(dummy_msg, obj)
      }
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_send
      assert_proc = Proc.new {
        ary = []
        @assert.assert_send ary, :empty?
      }
      sub_assert_pass(assert_proc)
      assert_proc = Proc.new {
        ary = [2,3]
        @assert.assert_send ary, :empty?
      }
      sub_assert_raise_fail(assert_proc)
      assert_proc = Proc.new {
        str = "abc"
        @assert.assert_send str, :sub!, "z", "y"
      }
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_kind_of
      assert_proc = Proc.new {
        @assert.assert_kind_of(String, "string")
      }
      sub_assert_pass(assert_proc)
      assert_proc = Proc.new {
        @assert.assert_kind_of(Regexp, "string")
      }
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_instance_of
      assert_proc = Proc.new {
        @assert.assert_instance_of(String, "string")
      }
      sub_assert_pass(assert_proc)
      assert_proc = Proc.new {
        @assert.assert_instance_of(Object, "string")
      }
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_match
      assert_proc = Proc.new{
        @assert.assert_match('foostring', /foo/)
      }
      sub_assert_pass(assert_proc)
      assert_proc = Proc.new {
        @assert.assert_match('barstring', /foo/)
      }
      sub_assert_raise_fail(assert_proc)
      match = @assert.assert_match('foostring', /foo/)
      assert_instance_of(MatchData, match)
      assert_equal('foo', match[0])
    end

    def test_assert_matches
      assert_proc = Proc.new{
        @assert.assert_matches('foostring', /foo/)
      }
      sub_assert_pass(assert_proc)
      assert_proc = Proc.new {
        @assert.assert_matches('barstring', /foo/)
      }
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_not_match
      assert_proc = Proc.new{
        @assert.assert_not_match('barstring', /foo/)
      }
      sub_assert_pass(assert_proc)
      assert_proc = Proc.new {
        @assert.assert_not_match('foostring', /foo/)
      }
      sub_assert_raise_fail(assert_proc)
      assert_proc = Proc.new {
        @assert.assert_not_match('foobarbaz', /ba.+/)
      }
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_same
      flag = false
      e = "foo"
      a = e
      assert_proc = Proc.new {@assert.assert_same(e, a)}
      sub_assert_pass(assert_proc)

      a = "foo"
      sub_assert_raise_fail(assert_proc)
    end

    def test_assert_exception
      assert_proc = Proc.new{
        @assert.assert_exception(IOError) {
    raise IOError
        }
      }
      sub_assert_pass(assert_proc)

      assert_proc = Proc.new{
        @assert.assert_exception(StandardError) {
    raise IOError
        }
      }
      sub_assert_raise_fail(assert_proc)

      assert_proc = Proc.new{
        @assert.assert_exception(IOError, "Exception") {
    raise StandardError
        }
      }
      sub_assert_raise_fail(assert_proc)

      assert_proc = Proc.new {
        @assert.assert_exception(StandardError) {
    "No Exception raised in this block"
        }
      }
      sub_assert_raise_fail(assert_proc)

      assert_proc = Proc.new {
        @assert.assert_exception(StandardError) {
    exit(33)
        }
      }
      sub_assert_raise_fail(assert_proc)

      t = @assert.assert_exception(IOError) {
        raise IOError
      }
      assert_instance_of(IOError, t)
      t = @assert.assert_exception(NameError) {
        non_existent_method
      }
      assert_instance_of(NameError, t)
      t = @assert.assert_exception(SystemExit) {
        exit(33)
      }
      assert_instance_of(SystemExit, t)
    end

    def test_assert_no_exception
      assert_proc = Proc.new{
        @assert.assert_no_exception(IOError, ArgumentError) {
    "No Exception raised in this block"
        }
      }
      sub_assert_pass(assert_proc)

      assert_proc = Proc.new{
        @assert.assert_no_exception(IOError, ArgumentError) {
    raise StandardError, "Standard Error raised"
        }
      }
      sub_assert_raise_error(assert_proc)

      assert_proc = Proc.new{
        @assert.assert_no_exception(IOError, ArgumentError) {
    raise ArgumentError, "Bad Argument"
        }
      }
      sub_assert_raise_fail(assert_proc)

      assert_proc = Proc.new{
        @assert.assert_no_exception {
          raise ArgumentError, "Bad Argument"
        }
      }
      sub_assert_raise_fail(assert_proc)

      assert_proc = Proc.new{
        @assert.assert_no_exception {
          raise NameError, "Bad Name"
        }
      }
      sub_assert_raise_fail(assert_proc)
      assert_proc = Proc.new {
        @assert.assert_no_exception {
    raise NoMemoryError
        }
      }
      sub_assert_raise_fail(assert_proc)
    end

    def sub_assert_pass(p)
      flag = false
      err = nil
      begin
        p.call
        flag = true
      rescue
        err = $!
        flag = false
      end
      assert(flag, err.to_s)
    end

    def sub_assert_raise_fail(p)
      flag = false
      err = nil
      begin
        p.call
        flag = false
      rescue RUNIT::AssertionFailedError
        flag = true
        err = $!
      rescue Exception
        flag = false
        err = $!
      end
      assert(flag, err.to_s)
    end

    def sub_assert_raise_error(p)
      flag = false
      err = nil
      begin
        p.call
        flag = false
      rescue RUNIT::AssertionFailedError
        flag = false
        err = $!
      rescue Exception
        flag = true
        err = $!
      end
      assert(flag, err.to_s)
    end
  end
end
