# frozen_string_literal: true
require 'test/unit'
require 'tmpdir'

class TestTmpdir < Test::Unit::TestCase
  def test_tmpdir_modifiable
    tmpdir = Dir.tmpdir
    assert_not_predicate(tmpdir, :frozen?)
    tmpdir_org = tmpdir.dup
    tmpdir << "foo"
    assert_equal(tmpdir_org, Dir.tmpdir)
  end

  def test_world_writable
    omit "no meaning on this platform" if /mswin|mingw/ =~ RUBY_PLATFORM
    Dir.mktmpdir do |tmpdir|
      # ToDo: fix for parallel test
      envs = %w[TMPDIR TMP TEMP]
      oldenv = envs.each_with_object({}) {|v, h| h[v] = ENV.delete(v)}
      begin
        envs.each do |e|
          tmpdirx = File.join(tmpdir, e)
          ENV[e] = tmpdirx
          assert_not_equal(tmpdirx, assert_warn('') {Dir.tmpdir})
          File.write(tmpdirx, "")
          assert_not_equal(tmpdirx, assert_warn(/\A#{e} is not a directory/) {Dir.tmpdir})
          File.unlink(tmpdirx)
          ENV[e] = tmpdir
          assert_equal(tmpdir, Dir.tmpdir)
          File.chmod(0555, tmpdir)
          assert_not_equal(tmpdir, assert_warn(/\A#{e} is not writable/) {Dir.tmpdir})
          File.chmod(0777, tmpdir)
          assert_not_equal(tmpdir, assert_warn(/\A#{e} is world-writable/) {Dir.tmpdir})
          newdir = Dir.mktmpdir("d", tmpdir) do |dir|
            assert_file.directory? dir
            assert_equal(tmpdir, File.dirname(dir))
            dir
          end
          assert_file.not_exist?(newdir)
          File.chmod(01777, tmpdir)
          assert_equal(tmpdir, Dir.tmpdir)
          ENV[e] = nil
        end
      ensure
        ENV.update(oldenv)
      end
    end
  end

  def test_tmpdir_not_empty_parent
    Dir.mktmpdir do |tmpdir|
      envs = %w[TMPDIR TMP TEMP]
      oldenv = envs.each_with_object({}) {|v, h| h[v] = ENV.delete(v)}
      ENV[envs[0]] = ""
      ENV[envs[1]] = tmpdir
      assert_equal(tmpdir, Dir.tmpdir)
    ensure
      ENV.update(oldenv)
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

  def test_mktmpdir_not_empty_parent
    assert_raise(ArgumentError) do
      Dir.mktmpdir("foo", "")
    end

    path = Struct.new(:to_path).new("")
    assert_raise(ArgumentError) do
      Dir.mktmpdir("foo", path)
    end

    Dir.mktmpdir do |d|
      path = Struct.new(:to_path).new(d)
      assert_operator(Dir.mktmpdir("prefix-", path), :start_with?, d + "/prefix-")
    end
  end

  def assert_mktmpdir_traversal
    Dir.mktmpdir do |target|
      target = target.chomp('/') + '/'
      traversal_path = target.sub(/\A\w:/, '') # for DOSISH
      traversal_path = Array.new(target.count('/')-2, '..').join('/') + traversal_path
      [File::SEPARATOR, File::ALT_SEPARATOR].compact.each do |separator|
        actual = yield traversal_path.tr('/', separator)
        assert_not_send([File.absolute_path(actual), :start_with?, target])
      end
    end
  end

  def test_ractor
    assert_ractor(<<~'end;', require: "tmpdir")
      r = Ractor.new do
        Dir.mktmpdir() do |d|
          Ractor.yield d
          Ractor.receive
        end
      end
      dir = r.take
      assert_file.directory? dir
      r.send true
      r.take
      assert_file.not_exist? dir
    end;
  end
end
