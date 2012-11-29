require 'rubygems/test_case'
require 'rubygems/commands/pristine_command'

class TestGemCommandsPristineCommand < Gem::TestCase

  def setup
    super
    @cmd = Gem::Commands::PristineCommand.new
  end

  def test_execute
    a = quick_spec 'a' do |s|
      s.executables = %w[foo]
      s.files = %w[bin/foo lib/a.rb]
    end

    write_file File.join(@tempdir, 'lib', 'a.rb') do |fp|
      fp.puts "puts __FILE__"
    end
    write_file File.join(@tempdir, 'bin', 'foo') do |fp|
      fp.puts "#!/usr/bin/ruby"
    end

    install_gem a

    foo_path  = File.join @gemhome, 'gems', a.full_name, 'bin', 'foo'
    a_rb_path = File.join @gemhome, 'gems', a.full_name, 'lib', 'a.rb'

    write_file foo_path do |io|
      io.puts 'I changed it!'
    end

    write_file a_rb_path do |io|
      io.puts 'I changed it!'
    end

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "#!/usr/bin/ruby\n", File.read(foo_path), foo_path
    assert_equal "puts __FILE__\n", File.read(a_rb_path), a_rb_path

    out = @ui.output.split "\n"

    assert_equal "Restoring gems to pristine condition...", out.shift
    assert_equal "Restored #{a.full_name}", out.shift
    assert_empty out, out.inspect
  end

  def test_execute_all
    a = quick_spec 'a' do |s| s.executables = %w[foo] end
    write_file File.join(@tempdir, 'bin', 'foo') do |fp|
      fp.puts "#!/usr/bin/ruby"
    end

    install_gem a

    gem_bin  = File.join @gemhome, 'gems', a.full_name, 'bin', 'foo'
    gem_stub = File.join @gemhome, 'bin', 'foo'

    FileUtils.rm gem_bin
    FileUtils.rm gem_stub

    @cmd.handle_options %w[--all]

    use_ui @ui do
      @cmd.execute
    end

    assert File.exist?(gem_bin)
    assert File.exist?(gem_stub)

    out = @ui.output.split "\n"

    assert_equal "Restoring gems to pristine condition...", out.shift
    assert_equal "Restored #{a.full_name}", out.shift
    assert_empty out, out.inspect
  end

  def test_execute_no_extension
    a = quick_spec 'a' do |s| s.extensions << 'ext/a/extconf.rb' end

    ext_path = File.join @tempdir, 'ext', 'a', 'extconf.rb'
    write_file ext_path do |io|
      io.write '# extconf.rb'
    end

    util_build_gem a

    @cmd.options[:args] = %w[a]
    @cmd.options[:extensions] = false

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"

    assert_equal 'Restoring gems to pristine condition...', out.shift
    assert_equal "Skipped #{a.full_name}, it needs to compile an extension",
                 out.shift
    assert_empty out, out.inspect
  end

  def test_execute_with_extension_with_build_args
    a = quick_spec 'a' do |s| s.extensions << 'ext/a/extconf.rb' end

    ext_path = File.join @tempdir, 'ext', 'a', 'extconf.rb'
    write_file ext_path do |io|
      io.write <<-'RUBY'
      File.open "Makefile", "w" do |f|
        f.puts "all:\n\techo built\n"
        f.puts "install:\n\techo built\n"
      end
      RUBY
    end

    build_args = %w!--with-awesome=true --sweet!

    install_gem a, :build_args => build_args

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"

    assert_equal 'Restoring gems to pristine condition...', out.shift
    assert_equal "Building native extensions with: '--with-awesome=true --sweet'", out.shift
    assert_equal "This could take a while...", out.shift
    assert_equal "Restored #{a.full_name}", out.shift
    assert_empty out, out.inspect
  end

  def test_execute_many
    a = quick_spec 'a'
    b = quick_spec 'b'

    install_gem a
    install_gem b

    @cmd.options[:args] = %w[a b]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"

    assert_equal "Restoring gems to pristine condition...", out.shift
    assert_equal "Restored #{a.full_name}", out.shift
    assert_equal "Restored #{b.full_name}", out.shift
    assert_empty out, out.inspect
  end

  def test_execute_many_multi_repo
    a = quick_spec 'a'
    install_gem a

    Gem.clear_paths
    gemhome2 = File.join @tempdir, 'gemhome2'
    Gem.paths = { "GEM_PATH" => [gemhome2, @gemhome], "GEM_HOME" => gemhome2 }

    b = quick_spec 'b'
    install_gem b

    @cmd.options[:args] = %w[a b]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"

    assert_equal "Restoring gems to pristine condition...", out.shift
    assert_equal "Restored #{a.full_name}", out.shift
    assert_equal "Restored #{b.full_name}", out.shift
    assert_empty out, out.inspect

    assert_path_exists File.join(@gemhome, "gems", 'a-2')
    refute_path_exists File.join(gemhome2, "gems", 'a-2')
    assert_path_exists File.join(gemhome2, "gems", 'b-2')
    refute_path_exists File.join(@gemhome, "gems", 'b-2')
  end

  def test_execute_missing_cache_gem
    a_2 = quick_spec 'a', 2
    a_3 = quick_spec 'a', 3

    install_gem a_2
    install_gem a_3

    a_2_data = nil
    open File.join(@gemhome, 'cache', a_2.file_name), 'rb' do |fp|
      a_2_data = fp.read
    end

    util_setup_fake_fetcher
    util_setup_spec_fetcher a_2

    url = "http://gems.example.com/gems/#{a_2.file_name}"
    Gem::RemoteFetcher.fetcher.data[url] = a_2_data

    FileUtils.rm a_2.cache_file

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"

    [
      "Restoring gems to pristine condition...",
      "Restored a-1",
      "Cached gem for a-2 not found, attempting to fetch...",
      "Restored a-2",
      "Restored a-3.a",
      "Restored a-3",
    ].each do |line|
      assert_equal line, out.shift
    end

    assert_empty out, out.inspect
  end

  def test_execute_no_gem
    @cmd.options[:args] = %w[]

    e = assert_raises Gem::CommandLineError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match %r|at least one gem name|, e.message
  end

  def test_execute_only_executables
    a = quick_spec 'a' do |s|
      s.executables = %w[foo]
      s.files = %w[bin/foo lib/a.rb]
    end
    write_file File.join(@tempdir, 'lib', 'a.rb') do |fp|
      fp.puts "puts __FILE__"
    end
    write_file File.join(@tempdir, 'bin', 'foo') do |fp|
      fp.puts "#!/usr/bin/ruby"
    end

    install_gem a

    gem_lib  = File.join @gemhome, 'gems', a.full_name, 'lib', 'a.rb'
    gem_exec = File.join @gemhome, 'bin', 'foo'

    FileUtils.rm gem_exec
    FileUtils.rm gem_lib

    @cmd.handle_options %w[--all --only-executables]

    use_ui @ui do
      @cmd.execute
    end

    assert File.exist? gem_exec
    refute File.exist? gem_lib
  end

  def test_execute_default_gem
    default_gem_spec = new_default_spec("default", "2.0.0.0",
                                        nil, "default/gem.rb")
    install_default_specs(default_gem_spec)

    @cmd.options[:args] = %w[default]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal([
                   "Restoring gems to pristine condition...",
                   "Skipped default-2.0.0.0, it is a default gem",
                 ],
                 @ui.output.split("\n"))
    assert_empty(@ui.error)
  end
end

