# frozen_string_literal: false
require 'test/unit'
require 'yaml/store'
require 'tmpdir'

class YAMLStoreTest < Test::Unit::TestCase
  def setup
    @yaml_store_file = File.join(Dir.tmpdir, "yaml_store.tmp.#{Process.pid}")
    @yaml_store = YAML::Store.new(@yaml_store_file)
  end

  def teardown
    File.unlink(@yaml_store_file) rescue nil
  end

  def test_opening_new_file_in_readonly_mode_should_result_in_empty_values
    @yaml_store.transaction(true) do
      assert_nil @yaml_store[:foo]
      assert_nil @yaml_store[:bar]
    end
  end

  def test_opening_new_file_in_readwrite_mode_should_result_in_empty_values
    @yaml_store.transaction do
      assert_nil @yaml_store[:foo]
      assert_nil @yaml_store[:bar]
    end
  end

  def test_data_should_be_loaded_correctly_when_in_readonly_mode
    @yaml_store.transaction do
      @yaml_store[:foo] = "bar"
    end
    @yaml_store.transaction(true) do
      assert_equal "bar", @yaml_store[:foo]
    end
  end

  def test_data_should_be_loaded_correctly_when_in_readwrite_mode
    @yaml_store.transaction do
      @yaml_store[:foo] = "bar"
    end
    @yaml_store.transaction do
      assert_equal "bar", @yaml_store[:foo]
    end
  end

  def test_changes_after_commit_are_discarded
    @yaml_store.transaction do
      @yaml_store[:foo] = "bar"
      @yaml_store.commit
      @yaml_store[:foo] = "baz"
    end
    @yaml_store.transaction(true) do
      assert_equal "bar", @yaml_store[:foo]
    end
  end

  def test_changes_are_not_written_on_abort
    @yaml_store.transaction do
      @yaml_store[:foo] = "bar"
      @yaml_store.abort
    end
    @yaml_store.transaction(true) do
      assert_nil @yaml_store[:foo]
    end
  end

  def test_writing_inside_readonly_transaction_raises_error
    assert_raise(PStore::Error) do
      @yaml_store.transaction(true) do
        @yaml_store[:foo] = "bar"
      end
    end
  end

  def test_thread_safe
    q1 = Queue.new
    assert_raise(PStore::Error) do
      th = Thread.new do
        @yaml_store.transaction do
          @yaml_store[:foo] = "bar"
          q1.push true
          sleep
        end
      end
      begin
        q1.pop
        @yaml_store.transaction {}
      ensure
        th.kill
        th.join
      end
    end
    q2 = Queue.new
    begin
      yaml_store = YAML::Store.new(second_file, true)
      cur = Thread.current
      th = Thread.new do
        yaml_store.transaction do
          yaml_store[:foo] = "bar"
          q1.push true
          q2.pop
          # wait for cur to enter a transaction
          sleep 0.1 until cur.stop?
        end
      end
      begin
        q1.pop
        q2.push true
        assert_equal("bar", yaml_store.transaction { yaml_store[:foo] })
      ensure
        th.join
      end
    end
  ensure
    File.unlink(second_file) rescue nil
  end

  def test_nested_transaction_raises_error
    assert_raise(PStore::Error) do
      @yaml_store.transaction { @yaml_store.transaction { } }
    end
    yaml_store = YAML::Store.new(second_file, true)
    assert_raise(PStore::Error) do
      yaml_store.transaction { yaml_store.transaction { } }
    end
  ensure
    File.unlink(second_file) rescue nil
  end

  # Test that PStore's file operations do not blow up when default encodings are set
  def test_yaml_store_files_are_accessed_as_binary_files
    bug5311 = '[ruby-core:39503]'
    n = 128
    assert_in_out_err(["-Eutf-8:utf-8", "-ryaml/store", "-", @yaml_store_file], <<-SRC, [bug5311], [], bug5311, timeout: 15)
      @yaml_store = YAML::Store.new(ARGV[0])
      (1..#{n}).each do |i|
        @yaml_store.transaction {@yaml_store["Key\#{i}"] = "value \#{i}"}
      end
      @yaml_store.transaction {@yaml_store["Bug5311"] = '#{bug5311}'}
      puts @yaml_store.transaction {@yaml_store["Bug5311"]}
    SRC
    assert_equal(bug5311, @yaml_store.transaction {@yaml_store["Bug5311"]}, bug5311)
  end

  def second_file
    File.join(Dir.tmpdir, "yaml_store.tmp2.#{Process.pid}")
  end

  def test_with_options
    bug12800 = '[ruby-dev:49821]'
    default_yaml = "---\na:\n- - b\n"
    indentation_3_yaml = "---\na:\n-  - b\n"

    @yaml_store = YAML::Store.new(@yaml_store_file)
    @yaml_store.transaction do
      @yaml_store['a'] = [['b']]
    end
    assert_equal(default_yaml, File.read(@yaml_store_file), bug12800)

    @yaml_store = YAML::Store.new(@yaml_store_file, true)
    @yaml_store.transaction do
      @yaml_store['a'] = [['b']]
    end
    assert_equal(default_yaml, File.read(@yaml_store_file), bug12800)

    @yaml_store = YAML::Store.new(@yaml_store_file, indentation: 3)
    @yaml_store.transaction do
      @yaml_store['a'] = [['b']]
    end
    assert_equal(indentation_3_yaml, File.read(@yaml_store_file), bug12800)

    @yaml_store = YAML::Store.new(@yaml_store_file, true, indentation: 3)
    @yaml_store.transaction do
      @yaml_store['a'] = [['b']]
    end
    assert_equal(indentation_3_yaml, File.read(@yaml_store_file), bug12800)
  end
end
