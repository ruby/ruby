require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/commands/install_command'

class TestGemCommandsInstallCommand < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Commands::InstallCommand.new
    @cmd.options[:generate_rdoc] = false
    @cmd.options[:generate_ri] = false
  end

  def test_execute_include_dependencies
    @cmd.options[:include_dependencies] = true
    @cmd.options[:args] = []

    assert_raise Gem::CommandLineError do
      use_ui @ui do
        @cmd.execute
      end
    end

    output = @ui.output.split "\n"
    assert_equal "INFO:  `gem install -y` is now default and will be removed",
                 output.shift
    assert_equal "INFO:  use --ignore-dependencies to install only the gems you list",
                 output.shift
    assert output.empty?, output.inspect
  end

  def test_execute_local
    util_setup_fake_fetcher
    @cmd.options[:domain] = :local

    gem1 = quick_gem 'gem_one'
    util_build_gem gem1
    FileUtils.mv File.join(@gemhome, 'cache', "#{@gem1.full_name}.gem"),
                 File.join(@tempdir)

    @cmd.options[:args] = [gem1.name]

    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        Dir.chdir @tempdir
        @cmd.execute
      ensure
        Dir.chdir orig_dir
      end
    end

    out = @ui.output.split "\n"
    assert_equal "Successfully installed #{@gem1.full_name}", out.shift
    assert_equal "1 gem installed", out.shift
    assert out.empty?, out.inspect
  end

  def test_execute_local_missing
    util_setup_fake_fetcher
    @cmd.options[:domain] = :local

    @cmd.options[:args] = %w[gem_one]

    use_ui @ui do
      @cmd.execute
    end

    # HACK no repository was checked
    assert_equal "ERROR:  could not find gem_one locally or in a repository\n",
                 @ui.error
  end

  def test_execute_no_gem
    @cmd.options[:args] = %w[]

    assert_raise Gem::CommandLineError do
      @cmd.execute
    end
  end

  def test_execute_nonexistent
    util_setup_fake_fetcher
    @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}"] =
      @source_index.dump

    @cmd.options[:args] = %w[nonexistent]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "ERROR:  could not find nonexistent locally or in a repository\n",
                 @ui.error
  end

  def test_execute_remote
    @cmd.options[:generate_rdoc] = true
    @cmd.options[:generate_ri] = true
    util_setup_fake_fetcher

    util_build_gem @gem1
    @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}"] =
      @source_index.dump
    @fetcher.data["#{@gem_repo}/gems/gem_one-0.0.2.gem"] =
      File.read(File.join(@gemhome, 'cache', "#{@gem1.full_name}.gem"))

    @cmd.options[:args] = [@gem1.name]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_match %r|Bulk updating|, out.shift
    assert_equal "Successfully installed #{@gem1.full_name}", out.shift
    assert_equal "1 gem installed", out.shift
    assert_equal "Installing ri documentation for #{@gem1.full_name}...",
                 out.shift
    assert_equal "Installing RDoc documentation for #{@gem1.full_name}...",
                 out.shift
    assert out.empty?, out.inspect
  end

  def test_execute_two
    util_setup_fake_fetcher
    @cmd.options[:domain] = :local

    gem1 = quick_gem 'gem_one'
    util_build_gem gem1
    FileUtils.mv File.join(@gemhome, 'cache', "#{@gem1.full_name}.gem"),
                 File.join(@tempdir)

    gem2 = quick_gem 'gem_two'
    util_build_gem gem2
    FileUtils.mv File.join(@gemhome, 'cache', "#{@gem2.full_name}.gem"),
                 File.join(@tempdir)

    @cmd.options[:args] = [gem1.name, gem2.name]

    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        Dir.chdir @tempdir
        @cmd.execute
      ensure
        Dir.chdir orig_dir
      end
    end

    out = @ui.output.split "\n"
    assert_equal "Successfully installed #{@gem1.full_name}", out.shift
    assert_equal "Successfully installed #{@gem2.full_name}", out.shift
    assert_equal "2 gems installed", out.shift
    assert out.empty?, out.inspect
  end

end

