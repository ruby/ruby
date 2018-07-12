# frozen_string_literal: false
require 'test/unit'
require 'irb'
require 'irb/lc/error'

module TestIRB
  class TestLoadPathPrependOption < Test::Unit::TestCase
    def test_valid_load_path
      begin
        path = File.expand_path('lib', Dir.pwd)
        IRB.parse_opts(argv: ['-I', path])
        assert_equal($LOAD_PATH.first, path)
      ensure
        $LOAD_PATH.delete($LOAD_PATH.first)
      end
    end

    def test_invalid_load_path
      path = File.expand_path('non-existant-path')

      assert_raise(IRB::LoadPathDoesNotExist) do
        IRB.parse_opts(argv: ['-I', path])
      end
    end

    def test_nil_load_path
      assert_raise(IRB::LoadPathDoesNotExist) do
        IRB.parse_opts(argv: ['-I'])
      end
    end
  end
end
