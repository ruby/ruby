require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/commands/pristine_command'

class TestGemCommandsPristineCommand < RubyGemTestCase

  def setup
    super
    @cmd = Gem::Commands::PristineCommand.new
  end

  def test_execute
    a = quick_gem 'a' do |s| s.executables = %w[foo] end
    FileUtils.mkdir_p File.join(@tempdir, 'bin')
    File.open File.join(@tempdir, 'bin', 'foo'), 'w' do |fp|
      fp.puts "#!/usr/bin/ruby"
    end

    install_gem a

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"

    assert_equal "Restoring gem(s) to pristine condition...", out.shift
    assert_equal "#{a.full_name} is in pristine condition", out.shift
    assert out.empty?, out.inspect
  end

  def test_execute_all
    a = quick_gem 'a' do |s| s.executables = %w[foo] end
    FileUtils.mkdir_p File.join(@tempdir, 'bin')
    File.open File.join(@tempdir, 'bin', 'foo'), 'w' do |fp|
      fp.puts "#!/usr/bin/ruby"
    end

    install_gem a

    gem_bin = File.join @gemhome, 'gems', "#{a.full_name}", 'bin', 'foo'

    FileUtils.rm gem_bin

    @cmd.handle_options %w[--all]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"

    assert_equal "Restoring gem(s) to pristine condition...", out.shift
    assert_equal "Restoring 1 file to #{a.full_name}...", out.shift
    assert_equal "  #{gem_bin}", out.shift
    assert out.empty?, out.inspect
  end

  def test_execute_missing_cache_gem
    a = quick_gem 'a' do |s| s.executables = %w[foo] end
    FileUtils.mkdir_p File.join(@tempdir, 'bin')
    File.open File.join(@tempdir, 'bin', 'foo'), 'w' do |fp|
      fp.puts "#!/usr/bin/ruby"
    end

    install_gem a

    FileUtils.rm File.join(@gemhome, 'cache', "#{a.full_name}.gem")

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"

    assert_equal "Restoring gem\(s\) to pristine condition...", out.shift
    assert out.empty?, out.inspect

    assert_equal "ERROR:  Cached gem for #{a.full_name} not found, use `gem install` to restore\n",
                 @ui.error
  end

  def test_execute_no_gem
    @cmd.options[:args] = %w[]

    e = assert_raise Gem::CommandLineError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match %r|specify a gem name|, e.message
  end

end

