require 'test/unit'
require_relative '../../ruby/envutil'
require '-test-/marshal/usr'

module Bug end

module Bug::Marshal
  class TestUsrMarshal < Test::Unit::TestCase
    def old_dump
      @old_dump ||=
        begin
          src = "module Bug; module Marshal; class UsrMarshal; def initialize(val) @value = val; end; end; ::Marshal.dump(UsrMarshal.new(42), STDOUT); end; end"
          EnvUtil.invoke_ruby([], src, true)[0]
        end
    end

    def test_marshal
      v = ::Marshal.load(::Marshal.dump(UsrMarshal.new(42)))
      assert_instance_of(UsrMarshal, v)
      assert_equal(42, v.value)
    end

    def test_incompat
      e = assert_raise(ArgumentError) {::Marshal.load(old_dump)}
      assert_equal("dump format error", e.message)
    end

    def test_compat
      out, err = EnvUtil.invoke_ruby(["-r-test-/marshal/usr", "-r-test-/marshal/compat", "-e", "::Marshal.dump(::Marshal.load(STDIN), STDOUT)"], old_dump, true, true)
      assert_equal(::Marshal.dump(UsrMarshal.new(42)), out)
      assert_equal("", err)
    end
  end
end
