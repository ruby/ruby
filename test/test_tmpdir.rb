# frozen_string_literal: true
require 'test/unit'
require 'tmpdir'

class TestTmpdir < Test::Unit::TestCase
  def test_tmpdir_modifiable
    tmpdir = Dir.tmpdir
    assert_equal(false, tmpdir.frozen?)
    tmpdir_org = tmpdir.dup
    tmpdir << "foo"
    assert_equal(tmpdir_org, Dir.tmpdir)
  end

  def test_tmpdir_modifiable_safe
    Thread.new {
      $SAFE = 1
      tmpdir = Dir.tmpdir
      assert_equal(false, tmpdir.frozen?)
      tmpdir_org = tmpdir.dup
      tmpdir << "foo"
      assert_equal(tmpdir_org, Dir.tmpdir)
    }.join
  ensure
    $SAFE = 0
  end

  def test_world_writable
    skip "no meaning on this platform" if /mswin|mingw/ =~ RUBY_PLATFORM
    Dir.mktmpdir do |tmpdir|
      # ToDo: fix for parallel test
      olddir, ENV["TMPDIR"] = ENV["TMPDIR"], tmpdir
      begin
        assert_equal(tmpdir, Dir.tmpdir)
        File.chmod(0777, tmpdir)
        assert_not_equal(tmpdir, Dir.tmpdir)
        newdir = Dir.mktmpdir("d", tmpdir) do |dir|
          assert_file.directory? dir
          assert_equal(tmpdir, File.dirname(dir))
          dir
        end
        assert_file.not_exist?(newdir)
        File.chmod(01777, tmpdir)
        assert_equal(tmpdir, Dir.tmpdir)
      ensure
        ENV["TMPDIR"] = olddir
      end
    end
  end

  def test_no_homedir
    bug7547 = '[ruby-core:50793]'
    home, ENV["HOME"] = ENV["HOME"], nil
    dir = assert_nothing_raised(bug7547) do
      break Dir.mktmpdir("~")
    end
    assert_match(/\A~/, File.basename(dir), bug7547)
  ensure
    ENV["HOME"] = home
    Dir.rmdir(dir) if dir
  end

  def test_mktmpdir_nil
    Dir.mktmpdir(nil) {|d|
      assert_kind_of(String, d)
    }
  end

  def test_mktmpdir_mutate
    bug16918 = '[ruby-core:98563]'
    assert_nothing_raised(bug16918) do
      assert_mktmpdir_traversal do |traversal_path|
        Dir.mktmpdir(traversal_path + 'foo') do |actual|
          actual << "foo"
        end
      end
    end
  end

  def test_mktmpdir_traversal
    assert_mktmpdir_traversal do |traversal_path|
      Dir.mktmpdir(traversal_path + 'foo') do |actual|
        actual
      end
    end
  end

  def test_mktmpdir_traversal_array
    assert_mktmpdir_traversal do |traversal_path|
      Dir.mktmpdir([traversal_path, 'foo']) do |actual|
        actual
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
end
