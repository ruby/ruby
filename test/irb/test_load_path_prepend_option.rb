# frozen_string_literal: false
require 'test/unit'
require 'irb'
require 'irb/lc/error'

module TestIRB
  class TestLoadPathPrependOption < Test::Unit::TestCase
    def test_valid_load_path
      begin
        path = File.dirname(__FILE__)

        IRB.parse_opts(argv: ['-I', path])

        assert_equal($LOAD_PATH.first, path)
      ensure
        $LOAD_PATH.delete($LOAD_PATH.first)
      end
    end

    def test_multiple_valid_load_paths
      begin
        this_dir = __dir__
        enclosing_dir = File.expand_path('..', __dir__)

        IRB.parse_opts(argv: ['-I', this_dir + File::PATH_SEPARATOR + enclosing_dir])

        assert_equal($LOAD_PATH[0], this_dir)
        assert_equal($LOAD_PATH[1], enclosing_dir)
      ensure
        $LOAD_PATH.delete(this_dir)
        $LOAD_PATH.delete(enclosing_dir)
      end
    end

    def test_valid_and_invalid_load_paths
      this_dir = __dir__
      invalid_dir = File.expand_path('non-existant-path')

      assert_raise_with_message(IRB::LoadPathDoesNotExist, "Load path does not exist: #{invalid_dir}") do
        IRB.parse_opts(argv: ['-I', this_dir + File::PATH_SEPARATOR + invalid_dir])
      end
    end

    def test_invalid_load_path
      invalid_dir = File.expand_path('non-existant-path')

      assert_raise_with_message(IRB::LoadPathDoesNotExist, "Load path does not exist: #{invalid_dir}") do
        IRB.parse_opts(argv: ['-I', invalid_dir])
      end
    end

    def test_nil_load_path
      assert_raise(IRB::LoadPathArgumentMissing) do
        IRB.parse_opts(argv: ['-I'])
      end
    end

    def test_empty_string_load_path
      assert_raise(IRB::LoadPathArgumentMissing) do
        IRB.parse_opts(argv: ['-I', '  '])
      end
    end
  end
end
