# frozen_string_literal: false
require 'test/unit'
require 'tmpdir'
require 'fileutils'

class TestFileUnlinkRecursive < Test::Unit::TestCase
  def setup
    File.unlink(recursive: true)
    @root = File.realpath(Dir.mktmpdir('ruby-unlink'))
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def test_tree
    path = File.join(@root, 'tree')
    FileUtils.mkdir_p("#{path}/a/b")
    File.write("#{path}/a/file", 'content')
    File.write("#{path}/.hidden", 'content')
    assert_equal(1, File.unlink(path, recursive: true))
    assert_file.not_exist?(path)
    assert_file.directory?(@root)
  end

  def test_deep_tree
    path = File.join(@root, 'tree')
    FileUtils.mkdir_p(path + '/a' * 100)
    assert_equal(1, File.unlink(path, recursive: true))
    assert_file.not_exist?(path)
  end

  def test_entry_names
    path = File.join(@root, 'tree')
    Dir.mkdir(path)
    names = ['a', '.a', '..a', 'a' * 200]
    names << '...' unless windows?
    names.each do |name|
      Dir.mkdir("#{path}/#{name}")
      File.write("#{path}/#{name}/file", 'content')
    end
    assert_equal(1, File.unlink(path, recursive: true))
    assert_file.not_exist?(path)
  end

  def test_descriptor_exhaustion
    path = File.join(@root, 'tree')
    FileUtils.mkdir_p(path + '/a' * 64)
    assert_separately([], <<~RUBY)
      path = #{path.dump}
      soft, hard = Process.getrlimit(:NOFILE)
      before = Dir.children('/dev/fd').size
      begin
        Process.setrlimit(:NOFILE, [soft, 32].min, hard)
        3.times do
          assert_raise(Errno::EMFILE) {File.unlink(path, recursive: true)}
        end
      ensure
        Process.setrlimit(:NOFILE, soft, hard)
      end
      assert_equal(before, Dir.children('/dev/fd').size)
      assert_equal(1, File.unlink(path, recursive: true))
    RUBY
    assert_file.not_exist?(path)
  end if !windows? && File.directory?('/dev/fd')

  def test_files_and_multiple_paths
    paths = %w[file tree].map {|name| File.join(@root, name)}
    File.write(paths[0], 'content')
    Dir.mkdir(paths[1])
    assert_equal(2, File.unlink(*paths, recursive: true))
    paths.each {|path| assert_file.not_exist?(path)}
    assert_equal(0, File.unlink(recursive: true))
  end

  def test_default_and_false
    path = File.join(@root, 'tree')
    Dir.mkdir(path)
    assert_raise(Errno::EPERM, Errno::EISDIR, Errno::EACCES) {File.unlink(path)}
    assert_raise(Errno::EPERM, Errno::EISDIR, Errno::EACCES) {File.unlink(path, recursive: false)}
    assert_file.directory?(path)
    file = File.join(path, 'file')
    File.write(file, 'content')
    assert_equal(1, File.unlink(file, recursive: false))
  end

  def test_arguments
    path = File.join(@root, 'file')
    File.write(path, 'content')
    [nil, 1, :true].each do |value|
      assert_raise(ArgumentError) {File.unlink(path, recursive: value)}
    end
    assert_raise(ArgumentError) {File.unlink(path, unknown: true)}
    assert_raise(TypeError) {File.unlink(path, Object.new, recursive: true)}
    assert_file.exist?(path)
    arg = Object.new
    arg.define_singleton_method(:to_path) {path.freeze}
    assert_equal(1, File.unlink(arg, recursive: true))
    assert_equal(File.join(@root, 'file'), path)
  end

  def test_missing_path
    assert_raise(Errno::ENOENT) {File.unlink(File.join(@root, 'missing'), recursive: true)}
    assert_raise(Errno::ENOENT) {File.unlink('', recursive: true)}
  end

  def test_keyword_hash
    options = {recursive: true}.freeze
    assert_equal(0, File.unlink(**options))
    assert_equal({recursive: true}, options)
    [{unknown: true}, {recursive: true, unknown: true}].each do |keywords|
      keywords.freeze
      error = assert_raise(ArgumentError) {File.unlink(**keywords)}
      assert_equal('unknown keyword: :unknown', error.message)
      assert_equal(true, keywords[:unknown])
    end
  end

  def test_alias
    path = File.join(@root, 'tree')
    Dir.mkdir(path)
    assert_equal(File.method(:unlink), File.method(:delete))
    assert_equal(1, File.delete(path, recursive: true))
  end

  def test_relative_and_trailing_separators
    Dir.chdir(@root) do
      FileUtils.mkdir_p('tree/a/b')
      assert_equal(1, File.unlink('./tree///', recursive: true))
      assert_file.not_exist?('tree')
    end
  end

  def test_reject_root_and_dot
    File.write(File.join(@root, 'keep'), 'content')
    Dir.chdir(@root) do
      ['/', '///', '.', './', '..', '../', "#{@root}/."].each do |path|
        assert_raise(Errno::EINVAL, Errno::EBUSY) {File.unlink(path, recursive: true)}
      end
      assert_equal('content', File.read('keep'))
    end
  end

  def test_symlinks
    outside = File.join(@root, 'outside')
    tree = File.join(@root, 'tree')
    Dir.mkdir(outside)
    Dir.mkdir(tree)
    File.write("#{outside}/keep", 'content')
    begin
      File.symlink(outside, "#{tree}/link")
    rescue NotImplementedError, Errno::EACCES, Errno::EPERM
      omit 'symlink is not supported'
    end
    File.symlink('missing', "#{tree}/dangling")
    File.symlink('.', "#{tree}/loop")
    assert_equal(1, File.unlink(tree, recursive: true))
    assert_equal('content', File.read("#{outside}/keep"))
    ["#{@root}/link", "#{@root}/link/"].each do |path|
      File.symlink(outside, "#{@root}/link")
      assert_equal(1, File.unlink(path, recursive: true))
      assert_equal('content', File.read("#{outside}/keep"))
    end
  end

  def test_nonascii_path
    path = File.join(@root, '日本語/親/子')
    FileUtils.mkdir_p(path)
    File.write("#{path}/ファイル", 'content')
    assert_equal(1, File.unlink(File.join(@root, '日本語'), recursive: true))
    assert_file.not_exist?(path)
  rescue EncodingError => e
    omit e.message
  end

  def test_permission_error
    path = File.join(@root, 'tree')
    Dir.mkdir(path)
    File.write("#{path}/keep", 'content')
    File.chmod(0o500, path)
    assert_raise(Errno::EACCES) {File.unlink(path, recursive: true)}
    assert_equal('content', File.read("#{path}/keep"))
  ensure
    File.chmod(0o700, path) if path && File.directory?(path)
  end if !windows? && Process.euid != 0

  if windows?
    def test_windows_paths
      [File.expand_path('/'), 'C:', 'C:\\', '\\\\server\\share\\'].each do |path|
        assert_raise(Errno::EBUSY) {File.unlink(path, recursive: true)}
      end
      path = File.join(@root, 'tree')
      FileUtils.mkdir_p("#{path}/a/b")
      assert_equal(1, File.unlink(path.tr('/', '\\') + '\\', recursive: true))
      assert_file.not_exist?(path)
    end

    def test_windows_readonly_file
      path = File.join(@root, 'tree')
      Dir.mkdir(path)
      File.write("#{path}/file", 'content')
      File.chmod(0o444, "#{path}/file")
      assert_equal(1, File.unlink(path, recursive: true))
      assert_file.not_exist?(path)
    end

    def test_windows_sharing_violation
      path = File.join(@root, 'file')
      File.write(path, 'content')
      File.open(path, File::RDONLY | File::SHARE_DELETE) do |file|
        assert_raise(Errno::EACCES) {File.unlink(path, recursive: true)}
        assert_equal('content', file.read)
      end
      assert_equal(1, File.unlink(path, recursive: true))
    end

    def test_windows_junction
      target = File.join(@root, 'outside')
      link = File.join(@root, 'link')
      Dir.mkdir(target)
      File.write("#{target}/keep", 'content')
      assert(system('mklink', '/J', link.tr('/', '\\'), target.tr('/', '\\'),
                    out: File::NULL, err: File::NULL))
      assert_raise(Errno::ENOTDIR) {File.unlink("#{link}/keep", recursive: true)}
      assert_equal('content', File.read("#{target}/keep"))
      assert_equal(1, File.unlink(link, recursive: true))
      assert_equal('content', File.read("#{target}/keep"))
    end
  end
end
