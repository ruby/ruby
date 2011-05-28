require 'test/unit'
require 'pstore'

class PStoreTest < Test::Unit::TestCase
  def setup
    @pstore_file = "pstore.tmp.#{Process.pid}"
    @pstore = PStore.new(@pstore_file)
  end

  def teardown
    File.unlink(@pstore_file) rescue nil
  end

  def test_opening_new_file_in_readonly_mode_should_result_in_empty_values
    @pstore.transaction(true) do
      assert_nil @pstore[:foo]
      assert_nil @pstore[:bar]
    end
  end

  def test_opening_new_file_in_readwrite_mode_should_result_in_empty_values
    @pstore.transaction do
      assert_nil @pstore[:foo]
      assert_nil @pstore[:bar]
    end
  end

  def test_data_should_be_loaded_correctly_when_in_readonly_mode
    @pstore.transaction do
      @pstore[:foo] = "bar"
    end
    @pstore.transaction(true) do
      assert_equal "bar", @pstore[:foo]
    end
  end

  def test_data_should_be_loaded_correctly_when_in_readwrite_mode
    @pstore.transaction do
      @pstore[:foo] = "bar"
    end
    @pstore.transaction do
      assert_equal "bar", @pstore[:foo]
    end
  end

  def test_changes_after_commit_are_discarded
    @pstore.transaction do
      @pstore[:foo] = "bar"
      @pstore.commit
      @pstore[:foo] = "baz"
    end
    @pstore.transaction(true) do
      assert_equal "bar", @pstore[:foo]
    end
  end

  def test_changes_are_not_written_on_abort
    @pstore.transaction do
      @pstore[:foo] = "bar"
      @pstore.abort
    end
    @pstore.transaction(true) do
      assert_nil @pstore[:foo]
    end
  end

  def test_writing_inside_readonly_transaction_raises_error
    assert_raise(PStore::Error) do
      @pstore.transaction(true) do
        @pstore[:foo] = "bar"
      end
    end
  end

  def test_thread_safe
    assert_raise(PStore::Error) do
      flag = false
      Thread.new do
        @pstore.transaction do
          @pstore[:foo] = "bar"
          flag = true
          sleep 1
        end
      end
      until flag; end
      @pstore.transaction {}
    end
    assert_block do
      pstore = PStore.new("pstore.tmp2.#{Process.pid}",true)
      flag = false
      Thread.new do
        pstore.transaction do
          pstore[:foo] = "bar"
          flag = true
          sleep 1
        end
      end
      until flag; end
      pstore.transaction { pstore[:foo] == "bar" }
      File.unlink("pstore.tmp2.#{Process.pid}") rescue nil
    end
  end
  
  def test_nested_transaction_raises_error
    assert_raise(PStore::Error) do
      @pstore.transaction { @pstore.transaction { } }
    end
    pstore = PStore.new("pstore.tmp2.#{Process.pid}", true)
    assert_raise(PStore::Error) do
      pstore.transaction { pstore.transaction { } }
    end
  end
end
