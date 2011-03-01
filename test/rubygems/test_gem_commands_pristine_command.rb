######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems/test_case'
require 'rubygems/commands/pristine_command'

class TestGemCommandsPristineCommand < Gem::TestCase

  def setup
    super
    @cmd = Gem::Commands::PristineCommand.new
  end

  def test_execute
    a = quick_spec 'a' do |s| s.executables = %w[foo] end
    FileUtils.mkdir_p File.join(@tempdir, 'bin')
    File.open File.join(@tempdir, 'bin', 'foo'), 'w' do |fp|
      fp.puts "#!/usr/bin/ruby"
    end

    install_gem a

    foo_path = File.join @gemhome, 'gems', a.full_name, 'bin', 'foo'

    File.open foo_path, 'w' do |io|
      io.puts 'I changed it!'
    end

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "#!/usr/bin/ruby\n", File.read(foo_path), foo_path

    out = @ui.output.split "\n"

    assert_equal "Restoring gem(s) to pristine condition...", out.shift
    assert_equal "Restored #{a.full_name}", out.shift
    assert_empty out, out.inspect
  end

  def test_execute_all
    a = quick_spec 'a' do |s| s.executables = %w[foo] end
    FileUtils.mkdir_p File.join(@tempdir, 'bin')
    File.open File.join(@tempdir, 'bin', 'foo'), 'w' do |fp|
      fp.puts "#!/usr/bin/ruby"
    end

    install_gem a

    gem_bin = File.join @gemhome, 'gems', a.full_name, 'bin', 'foo'

    FileUtils.rm gem_bin

    @cmd.handle_options %w[--all]

    use_ui @ui do
      @cmd.execute
    end

    assert File.exist?(gem_bin)

    out = @ui.output.split "\n"

    assert_equal "Restoring gem(s) to pristine condition...", out.shift
    assert_equal "Restored #{a.full_name}", out.shift
    assert_empty out, out.inspect
  end

  def test_execute_missing_cache_gem
    a = quick_spec 'a' do |s|
      s.executables = %w[foo]
    end

    FileUtils.mkdir_p File.join(@tempdir, 'bin')

    File.open File.join(@tempdir, 'bin', 'foo'), 'w' do |fp|
      fp.puts "#!/usr/bin/ruby"
    end

    install_gem a

    a_data = nil
    open File.join(@gemhome, 'cache', a.file_name), 'rb' do |fp|
      a_data = fp.read
    end

    util_setup_fake_fetcher
    util_setup_spec_fetcher a

    Gem::RemoteFetcher.fetcher.data["http://gems.example.com/gems/#{a.file_name}"] = a_data

    FileUtils.rm Gem.cache_gem(a.file_name, @gemhome)

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"

    [
      "Restoring gem\(s\) to pristine condition...",
      "Restored a-1",
      "Cached gem for a-2 not found, attempting to fetch...",
      "Restored a-2",
      "Restored a-3.a"
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

    assert_match %r|specify a gem name|, e.message
  end

end

