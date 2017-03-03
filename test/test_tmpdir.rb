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
end
