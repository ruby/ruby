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

    assert_raises Gem::CommandLineError do
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

    FileUtils.mv File.join(@gemhome, 'cache', "#{@a2.full_name}.gem"),
                 File.join(@tempdir)

    @cmd.options[:args] = [@a2.name]

    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        Dir.chdir @tempdir
        e = assert_raises Gem::SystemExitException do
          @cmd.execute
        end
        assert_equal 0, e.exit_code
      ensure
        Dir.chdir orig_dir
      end
    end

    out = @ui.output.split "\n"
    assert_equal "Successfully installed #{@a2.full_name}", out.shift
    assert_equal "1 gem installed", out.shift
    assert out.empty?, out.inspect
  end

  def test_execute_local_missing
    util_setup_fake_fetcher
    @cmd.options[:domain] = :local

    @cmd.options[:args] = %w[no_such_gem]

    use_ui @ui do
      e = assert_raises Gem::SystemExitException do
        @cmd.execute
      end
      assert_equal 2, e.exit_code
    end

    # HACK no repository was checked
    assert_equal "ERROR:  could not find gem no_such_gem locally or in a repository\n",
                 @ui.error
  end

  def test_execute_no_gem
    @cmd.options[:args] = %w[]

    assert_raises Gem::CommandLineError do
      @cmd.execute
    end
  end

  def test_execute_nonexistent
    util_setup_fake_fetcher
    util_setup_spec_fetcher

    @cmd.options[:args] = %w[nonexistent]

    use_ui @ui do
      e = assert_raises Gem::SystemExitException do
        @cmd.execute
      end
      assert_equal 2, e.exit_code
    end

    assert_equal "ERROR:  could not find gem nonexistent locally or in a repository\n",
                 @ui.error
  end

  def test_execute_remote
    @cmd.options[:generate_rdoc] = true
    @cmd.options[:generate_ri] = true

    util_setup_fake_fetcher
    util_setup_spec_fetcher @a2

    @fetcher.data["#{@gem_repo}gems/#{@a2.full_name}.gem"] =
      read_binary(File.join(@gemhome, 'cache', "#{@a2.full_name}.gem"))

    @cmd.options[:args] = [@a2.name]

    use_ui @ui do
      e = assert_raises Gem::SystemExitException do
        @cmd.execute
      end
      assert_equal 0, e.exit_code
    end

    out = @ui.output.split "\n"
    assert_equal "Successfully installed #{@a2.full_name}", out.shift
    assert_equal "1 gem installed", out.shift
    assert_equal "Installing ri documentation for #{@a2.full_name}...",
                 out.shift
    assert_equal "Installing RDoc documentation for #{@a2.full_name}...",
                 out.shift
    assert out.empty?, out.inspect
  end

  def test_execute_two
    util_setup_fake_fetcher
    @cmd.options[:domain] = :local

    FileUtils.mv File.join(@gemhome, 'cache', "#{@a2.full_name}.gem"),
                 File.join(@tempdir)

    FileUtils.mv File.join(@gemhome, 'cache', "#{@b2.full_name}.gem"),
                 File.join(@tempdir)

    @cmd.options[:args] = [@a2.name, @b2.name]

    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        Dir.chdir @tempdir
        e = assert_raises Gem::SystemExitException do
          @cmd.execute
        end
        assert_equal 0, e.exit_code
      ensure
        Dir.chdir orig_dir
      end
    end

    out = @ui.output.split "\n"
    assert_equal "Successfully installed #{@a2.full_name}", out.shift
    assert_equal "Successfully installed #{@b2.full_name}", out.shift
    assert_equal "2 gems installed", out.shift
    assert out.empty?, out.inspect
  end

end

