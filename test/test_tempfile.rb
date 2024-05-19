# frozen_string_literal: true
require 'test/unit'
require 'tempfile'

class TestTempfile < Test::Unit::TestCase
  def initialize(*)
    super
    @tempfile = nil
  end

  def tempfile(*args, **kw, &block)
    t = Tempfile.new(*args, **kw, &block)
    @tempfile = (t unless block)
  end

  def teardown
    if @tempfile
      @tempfile.close!
    end
  end

  def test_leackchecker
    assert_instance_of(Tempfile, Tempfile.allocate)
  end

  def test_basic
    t = tempfile("foo")
    path = t.path
    t.write("hello world")
    t.close
    assert_equal "hello world", File.read(path)
  end

  def test_saves_in_given_directory
    subdir = File.join(Dir.tmpdir, "tempfile-test-#{rand}")
    Dir.mkdir(subdir)
    begin
      tempfile = Tempfile.new("foo", subdir)
      tempfile.close
      begin
        assert_equal subdir, File.dirname(tempfile.path)
      ensure
        tempfile.unlink
      end
    ensure
      Dir.rmdir(subdir)
    end
  end

  def test_basename
    t = tempfile("foo")
    assert_match(/^foo/, File.basename(t.path))
  end

  def test_default_basename
    t = tempfile
    assert_file.exist?(t.path)
  end

  def test_basename_with_suffix
    t = tempfile(["foo", ".txt"])
    assert_match(/^foo/, File.basename(t.path))
    assert_match(/\.txt$/, File.basename(t.path))
  end

  def test_dup
    t = tempfile
    t2 = t.dup
    t2.close
    assert_equal true, t2.closed?
    assert_equal false, t.closed?
  end

  def test_clone
    t = tempfile
    t2 = t.clone
    t2.close
    assert_equal true, t2.closed?
    assert_equal false, t.closed?
  end

  def test_unlink
    t = tempfile("foo")
    path = t.path

    t.close
    assert_file.exist?(path)

    t.unlink
    assert_file.not_exist?(path)

    assert_nil t.path
  end

  def test_unlink_silently_fails_on_windows
    tempfile = tempfile("foo")
    path = tempfile.path
    begin
      assert_nothing_raised do
        tempfile.unlink
      end
    ensure
      tempfile.close
      File.unlink(path) if File.exist?(path)
    end
  end

  def test_unlink_before_close_works_on_posix_systems
    tempfile = tempfile("foo")
    begin
      path = tempfile.path
      tempfile.unlink
      assert_file.not_exist?(path)
      tempfile.write("hello ")
      tempfile.write("world\n")
      tempfile.rewind
      assert_equal "hello world\n", tempfile.read
    ensure
      tempfile.close
      tempfile.unlink
    end
  end unless /mswin|mingw/ =~ RUBY_PLATFORM

  def test_close_and_close_p
    t = tempfile("foo")
    assert_not_predicate(t, :closed?)
    t.close
    assert_predicate(t, :closed?)
  end

  def test_close_with_unlink_now_true_works
    t = tempfile("foo")
    path = t.path
    t.close(true)
    assert_predicate(t, :closed?)
    assert_nil t.path
    assert_file.not_exist?(path)
  end

  def test_close_with_unlink_now_true_does_not_unlink_if_already_unlinked
    t = tempfile("foo")
    path = t.path
    t.unlink
    File.open(path, "w").close
    begin
      t.close(true)
      assert_file.exist?(path)
    ensure
      File.unlink(path) rescue nil
    end
  end unless /mswin|mingw/ =~ RUBY_PLATFORM

  def test_close_bang_works
    t = tempfile("foo")
    path = t.path
    t.close!
    assert_predicate(t, :closed?)
    assert_nil t.path
    assert_file.not_exist?(path)
  end

  def test_close_bang_does_not_unlink_if_already_unlinked
    t = tempfile("foo")
    path = t.path
    t.unlink
    File.open(path, "w").close
    begin
      t.close!
      assert_file.exist?(path)
    ensure
      File.unlink(path) rescue nil
    end
  end unless /mswin|mingw/ =~ RUBY_PLATFORM

  def test_finalizer_does_not_unlink_if_already_unlinked
    assert_in_out_err('-rtempfile', <<-'EOS') do |(filename,*), (error,*)|
file = Tempfile.new('foo')
path = file.path
puts path
file.close!
File.open(path, "w").close
    EOS
      assert_file.exist?(filename)
      File.unlink(filename)
      assert_nil error
    end

    assert_in_out_err('-rtempfile', <<-'EOS') do |(filename,*), (error,*)|
file = Tempfile.new('foo')
path = file.path
file.unlink
puts path
File.open(path, "w").close
    EOS
      if !filename.empty?
        # POSIX unlink semantics supported, continue with test
        assert_file.exist?(filename)
        File.unlink(filename)
      end
      assert_nil error
    end
  end unless /mswin|mingw/ =~ RUBY_PLATFORM

  def test_close_does_not_make_path_nil
    t = tempfile("foo")
    t.close
    assert_not_nil t.path
  end

  def test_close_flushes_buffer
    t = tempfile("foo")
    t.write("hello")
    t.close
    assert_equal 5, File.size(t.path)
  end

  def test_tempfile_is_unlinked_when_ruby_exits
    assert_in_out_err('-rtempfile', <<-'EOS') do |(filename), (error)|
puts Tempfile.new('foo').path
    EOS
      assert_file.for("tempfile must not be exist after GC.").not_exist?(filename)
      assert_nil(error)
    end
  end

  def test_tempfile_finalizer_does_not_run_if_unlinked
    bug8768 = '[ruby-core:56521] [Bug #8768]'
    assert_in_out_err(%w(-rtempfile), <<-'EOS') do |(filename), (error)|
      tmp = Tempfile.new('foo')
      puts tmp.path
      tmp.close
      tmp.unlink
      $DEBUG = true
      EOS
      assert_file.not_exist?(filename)
      assert_nil(error, "#{bug8768} we used to get a confusing 'removing ...done' here")
    end
  end

  def test_size_flushes_buffer_before_determining_file_size
    t = tempfile("foo")
    t.write("hello")
    assert_equal 0, File.size(t.path)
    assert_equal 5, t.size
    assert_equal 5, File.size(t.path)
  end

  def test_size_works_if_file_is_closed
    t = tempfile("foo")
    t.write("hello")
    t.close
    assert_equal 5, t.size
  end

  def test_size_on_empty_file
    t = tempfile("foo")
    t.write("")
    t.close
    assert_equal 0, t.size
  end

  def test_concurrency
    threads = []
    tempfiles = []
    lock = Thread::Mutex.new
    cond = Thread::ConditionVariable.new
    start = false

    4.times do
      threads << Thread.new do
        lock.synchronize do
          while !start
            cond.wait(lock)
          end
        end
        result = []
        30.times do
          result << Tempfile.new('foo')
        end
        Thread.current[:result] = result
      end
    end

    lock.synchronize do
      start = true
      cond.broadcast
    end
    threads.each do |thread|
      thread.join
      tempfiles |= thread[:result]
    end
    filenames = tempfiles.map { |f| f.path }
    begin
      assert_equal filenames.size, filenames.uniq.size
    ensure
      tempfiles.each do |tempfile|
        tempfile.close!
      end
    end
  end

  module M
  end

  def test_extend
    o = tempfile("foo")
    o.extend M
    assert(M === o, "[ruby-dev:32932]")
  end

  def test_tempfile_encoding_nooption
    default_external=Encoding.default_external
    t = tempfile("TEST")
    t.write("\xE6\x9D\xBE\xE6\xB1\x9F")
    t.rewind
    assert_equal(default_external,t.read.encoding)
  end

  def test_tempfile_encoding_ascii8bit
    t = tempfile("TEST",:encoding=>"ascii-8bit")
    t.write("\xE6\x9D\xBE\xE6\xB1\x9F")
    t.rewind
    assert_equal(Encoding::ASCII_8BIT,t.read.encoding)
  end

  def test_tempfile_encoding_ascii8bit2
    t = tempfile("TEST",Dir::tmpdir,:encoding=>"ascii-8bit")
    t.write("\xE6\x9D\xBE\xE6\xB1\x9F")
    t.rewind
    assert_equal(Encoding::ASCII_8BIT,t.read.encoding)
  end

  def test_binmode
    t = tempfile("TEST", mode: IO::BINARY)
    if IO::BINARY.nonzero?
      assert(t.binmode?)
      t.open
      assert(t.binmode?, 'binmode after reopen')
    else
      assert_equal(0600, t.stat.mode & 0777)
    end
  end

  def test_create_with_block
    path = nil
    Tempfile.create("tempfile-create") {|f|
      path = f.path
      assert_file.exist?(path)
    }
    assert_file.not_exist?(path)

    Tempfile.create("tempfile-create") {|f|
      path = f.path
      f.close
      File.unlink(f.path)
    }
    assert_file.not_exist?(path)
  end

  def test_create_without_block
    path = nil
    f = Tempfile.create("tempfile-create")
    path = f.path
    assert_file.exist?(path)
    f.close
    assert_file.exist?(path)
  ensure
    f&.close
    File.unlink path if path
  end

  def test_create_default_basename
    path = nil
    Tempfile.create {|f|
      path = f.path
      assert_file.exist?(path)
    }
    assert_file.not_exist?(path)
  end

  def test_open
    Tempfile.open {|f|
      file = f.open
      assert_kind_of File, file
      assert_equal f.to_i, file.to_i
    }
  end

  def test_open_traversal_dir
    assert_mktmpdir_traversal do |traversal_path|
      t = Tempfile.open([traversal_path, 'foo'])
      t.path
    ensure
      t&.close!
    end
  end

  def test_new_traversal_dir
    assert_mktmpdir_traversal do |traversal_path|
      t = Tempfile.new(traversal_path + 'foo')
      t.path
    ensure
      t&.close!
    end
  end

  def test_create_traversal_dir
    assert_mktmpdir_traversal do |traversal_path|
      t = Tempfile.create(traversal_path + 'foo')
      t.path
    ensure
      if t
        t.close
        File.unlink(t.path)
      end
    end
  end


  def assert_mktmpdir_traversal
    Dir.mktmpdir do |target|
      target = target.chomp('/') + '/'
      traversal_path = target.sub(/\A\w:/, '') # for DOSISH
      traversal_path = Array.new(target.count('/')-2, '..').join('/') + traversal_path
      actual = yield traversal_path
      assert_not_send([File.absolute_path(actual), :start_with?, target])
    end
  end

  def test_create_io
    tmpio = Tempfile.create_io
    assert_equal(IO, tmpio.class)
    assert_equal(nil, tmpio.path)
    assert_equal(0600, tmpio.stat.mode & 0777)
    tmpio.puts "foo"
    tmpio.rewind
    assert_equal("foo\n", tmpio.read)
  ensure
    tmpio.close if tmpio
  end
end
