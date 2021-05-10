# frozen_string_literal: true
require_relative 'helper'
require 'yaml/store'
require 'tmpdir'

module Psych
  class YAML::Store
    alias :old_load :load

    def load(content)
      table = YAML.load(content, fallback: false)
      if table == false
        {}
      else
        table
      end
    end
  end

  unless defined?(Psych::Store)
    Psych::Store = YAML::Store
  end

  class YAMLStoreTest < TestCase
    def setup
      @dir = Dir.mktmpdir("rubytest-file")
      File.chown(-1, Process.gid, @dir)
      @yamlstore_file = make_tmp_filename("yamlstore")
      @yamlstore = YAML::Store.new(@yamlstore_file)
    end

    def teardown
      FileUtils.remove_entry_secure @dir
    end

    def make_tmp_filename(prefix)
      @dir + "/" + prefix + File.basename(__FILE__) + ".#{$$}.test"
    end

    def test_opening_new_file_in_readonly_mode_should_result_in_empty_values
      @yamlstore.transaction(true) do
        assert_nil @yamlstore["foo"]
        assert_nil @yamlstore["bar"]
      end
    end

    def test_opening_new_file_in_readwrite_mode_should_result_in_empty_values
      @yamlstore.transaction do
        assert_nil @yamlstore["foo"]
        assert_nil @yamlstore["bar"]
      end
    end

    def test_data_should_be_loaded_correctly_when_in_readonly_mode
      @yamlstore.transaction do
        @yamlstore["foo"] = "bar"
      end
      @yamlstore.transaction(true) do
        assert_equal "bar", @yamlstore["foo"]
      end
    end

    def test_data_should_be_loaded_correctly_when_in_readwrite_mode
      @yamlstore.transaction do
        @yamlstore["foo"] = "bar"
      end
      @yamlstore.transaction do
        assert_equal "bar", @yamlstore["foo"]
      end
    end

    def test_changes_after_commit_are_discarded
      @yamlstore.transaction do
        @yamlstore["foo"] = "bar"
        @yamlstore.commit
        @yamlstore["foo"] = "baz"
      end
      @yamlstore.transaction(true) do
        assert_equal "bar", @yamlstore["foo"]
      end
    end

    def test_changes_are_not_written_on_abort
      @yamlstore.transaction do
        @yamlstore["foo"] = "bar"
        @yamlstore.abort
      end
      @yamlstore.transaction(true) do
        assert_nil @yamlstore["foo"]
      end
    end

    def test_writing_inside_readonly_transaction_raises_error
      assert_raise(PStore::Error) do
        @yamlstore.transaction(true) do
          @yamlstore["foo"] = "bar"
        end
      end
    end
  end
end if defined?(Psych)
