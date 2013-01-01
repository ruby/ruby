require File.expand_path('../helper', __FILE__)
require 'fileutils'

class TestRakeDirectoryTask < Rake::TestCase
  include Rake

  def test_directory
    desc "DESC"

    directory "a/b/c"

    assert_equal FileCreationTask, Task["a"].class
    assert_equal FileCreationTask, Task["a/b"].class
    assert_equal FileCreationTask, Task["a/b/c"].class

    assert_nil             Task["a"].comment
    assert_nil             Task["a/b"].comment
    assert_equal "DESC",   Task["a/b/c"].comment

    verbose(false) {
      Task['a/b'].invoke
    }

    assert File.exist?("a/b")
    refute File.exist?("a/b/c")
  end

  if Rake::Win32.windows?
    def test_directory_win32
      desc "WIN32 DESC"
      directory 'c:/a/b/c'
      assert_equal FileTask, Task['c:'].class
      assert_equal FileCreationTask, Task['c:/a'].class
      assert_equal FileCreationTask, Task['c:/a/b'].class
      assert_equal FileCreationTask, Task['c:/a/b/c'].class
      assert_nil             Task['c:/'].comment
      assert_equal "WIN32 DESC",   Task['c:/a/b/c'].comment
      assert_nil             Task['c:/a/b'].comment
    end
  end

  def test_can_use_blocks
    runlist = []

    t1 = directory("a/b/c" => :t2) { |t| runlist << t.name }
    task(:t2) { |t| runlist << t.name }

    verbose(false) {
      t1.invoke
    }

    assert_equal Task["a/b/c"], t1
    assert_equal FileCreationTask, Task["a/b/c"].class
    assert_equal ["t2", "a/b/c"], runlist
    assert File.directory?("a/b/c")
  end
end
