# frozen_string_literal: false
require 'test/unit'
require 'pstore'
require 'tmpdir'

class PStoreTest < Test::Unit::TestCase
  def setup
    @pstore_file = File.join(Dir.tmpdir, "pstore.tmp.#{Process.pid}")
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
    q1 = Queue.new
    assert_raise(PStore::Error) do
      th = Thread.new do
        @pstore.transaction do
          @pstore[:foo] = "bar"
          q1.push true
          sleep
        end
      end
      begin
        q1.pop
        @pstore.transaction {}
      ensure
        th.kill
        th.join
      end
    end
    q2 = Queue.new
    begin
      pstore = PStore.new(second_file, true)
      cur = Thread.current
      th = Thread.new do
        pstore.transaction do
          pstore[:foo] = "bar"
          q1.push true
          q2.pop
          # wait for cur to enter a transaction
          sleep 0.1 until cur.stop?
        end
      end
      begin
        q1.pop
        q2.push true
        assert_equal("bar", pstore.transaction { pstore[:foo] })
      ensure
        th.join
      end
    end
  ensure
    File.unlink(second_file) rescue nil
  end

  def test_nested_transaction_raises_error
    assert_raise(PStore::Error) do
      @pstore.transaction { @pstore.transaction { } }
    end
    pstore = PStore.new(second_file, true)
    assert_raise(PStore::Error) do
      pstore.transaction { pstore.transaction { } }
    end
  ensure
    File.unlink(second_file) rescue nil
  end

  # Test that PStore's file operations do not blow up when default encodings are set
  def test_pstore_files_are_accessed_as_binary_files
    bug5311 = '[ruby-core:39503]'
    n = 128
    assert_in_out_err(["-Eutf-8:utf-8", "-rpstore", "-", @pstore_file], <<-SRC, [bug5311], [], bug5311, timeout: 15)
      @pstore = PStore.new(ARGV[0])
      (1..#{n}).each do |i|
        @pstore.transaction {@pstore["Key\#{i}"] = "value \#{i}"}
      end
      @pstore.transaction {@pstore["Bug5311"] = '#{bug5311}'}
      puts @pstore.transaction {@pstore["Bug5311"]}
    SRC
    assert_equal(bug5311, @pstore.transaction {@pstore["Bug5311"]}, bug5311)
  end

  def second_file
    File.join(Dir.tmpdir, "pstore.tmp2.#{Process.pid}")
  end
end
