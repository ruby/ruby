# frozen_string_literal: false

require_relative "../helper"

class TestCSVInterfaceDelegation < Test::Unit::TestCase
  class TestStringIO < self
    def setup
      @csv = CSV.new("h1,h2")
    end

    def test_flock
      assert_raise(NotImplementedError) do
        @csv.flock(File::LOCK_EX)
      end
    end

    def test_ioctl
      assert_raise(NotImplementedError) do
        @csv.ioctl(0)
      end
    end

    def test_stat
      assert_raise(NotImplementedError) do
        @csv.stat
      end
    end

    def test_to_i
      assert_raise(NotImplementedError) do
        @csv.to_i
      end
    end

    def test_binmode?
      assert_equal(false, @csv.binmode?)
    end

    def test_path
      assert_equal(nil, @csv.path)
    end

    def test_to_io
      assert_instance_of(StringIO, @csv.to_io)
    end
  end
end
