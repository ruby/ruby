# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/cleanup_command'
require 'rubygems/installer'

class TestGemCommandsCleanupCommand < Gem::TestCase

  def setup
    super

    @cmd = Gem::Commands::CleanupCommand.new

    @a_1 = util_spec 'a', 1
    @a_2 = util_spec 'a', 2

    install_gem @a_1
    install_gem @a_2
  end

  def test_handle_options_d
    @cmd.handle_options %w[-d]
    assert @cmd.options[:dryrun]
  end

  def test_handle_options_dry_run
    @cmd.handle_options %w[--dryrun]
    assert @cmd.options[:dryrun]
  end

  def test_handle_options_n
    @cmd.handle_options %w[-n]
    assert @cmd.options[:dryrun]
  end

  def test_handle_options_check_development
    @cmd.handle_options []
    assert @cmd.options[:check_dev]

    %w[-D --check-development].each do |options|
      @cmd.handle_options [options]
      assert @cmd.options[:check_dev]
    end

    %w[--no-check-development].each do |options|
      @cmd.handle_options [options]
      refute @cmd.options[:check_dev]
    end
  end

  def test_execute
    @cmd.options[:args] = %w[a]

    @cmd.execute

    refute_path_exists @a_1.gem_dir
  end

  def test_execute_all_dependencies
    @b_1 = util_spec 'b', 1 do |s|
      s.add_dependency 'a', '1'
    end

    @b_2 = util_spec 'b', 2 do |s|
      s.add_dependency 'a', '2'
    end

    install_gem @b_1
    install_gem @b_2

    @cmd.options[:args] = []

    @cmd.execute

    refute_path_exists @a_1.gem_dir
    refute_path_exists @b_1.gem_dir
  end

  def test_execute_dev_dependencies
    @b_1 = util_spec 'b', 1 do |s|
      s.add_development_dependency 'a', '1'
    end

    @c_1 = util_spec 'c', 1 do |s|
      s.add_development_dependency 'a', '2'
    end

    install_gem @b_1
    install_gem @c_1

    @cmd.handle_options %w[--check-development]

    @cmd.execute

    assert_path_exists @a_1.gem_dir
  end

  def test_execute_without_dev_dependencies
    @b_1 = util_spec 'b', 1 do |s|
      s.add_development_dependency 'a', '1'
    end

    @c_1 = util_spec 'c', 1 do |s|
      s.add_development_dependency 'a', '2'
    end

    install_gem @b_1
    install_gem @c_1

    @cmd.handle_options %w[--no-check-development]

    @cmd.execute

    refute_path_exists @a_1.gem_dir
  end

  def test_execute_all
    gemhome2 = File.join @tempdir, 'gemhome2'

    Gem.ensure_gem_subdirectories gemhome2

    Gem.use_paths @gemhome, gemhome2

    @b_1 = util_spec 'b', 1
    @b_2 = util_spec 'b', 2

    install_gem @b_1
    install_gem @b_2

    @cmd.options[:args] = []

    @cmd.execute

    assert_equal @gemhome, Gem.dir, 'GEM_HOME'
    assert_equal [@gemhome, gemhome2], Gem.path.sort, 'GEM_PATH'

    refute_path_exists @a_1.gem_dir
    refute_path_exists @b_1.gem_dir
  end

  def test_execute_all_user
    @a_1_1, = util_gem 'a', '1.1'
    @a_1_1 = install_gem @a_1_1 # pick up user install path

    Gem::Specification.dirs = [Gem.dir, Gem.user_dir]

    assert_path_exists @a_1.gem_dir
    assert_path_exists @a_1_1.gem_dir

    @cmd.options[:args] = %w[a]

    @cmd.execute

    refute_path_exists @a_1.gem_dir
    refute_path_exists @a_1_1.gem_dir
  end

  def test_execute_all_user_no_sudo
    FileUtils.chmod 0555, @gemhome

    @a_1_1, = util_gem 'a', '1.1'
    @a_1_1 = install_gem @a_1_1, :user_install => true # pick up user install path

    Gem::Specification.dirs = [Gem.dir, Gem.user_dir]

    assert_path_exists @a_1.gem_dir
    assert_path_exists @a_1_1.gem_dir

    @cmd.options[:args] = %w[a]

    @cmd.execute

    assert_path_exists @a_1.gem_dir
    assert_path_exists @a_1_1.gem_dir
  ensure
    FileUtils.chmod 0755, @gemhome
  end unless win_platform? || Process.uid.zero?

  def test_execute_dry_run
    @cmd.options[:args] = %w[a]
    @cmd.options[:dryrun] = true

    @cmd.execute

    assert_path_exists @a_1.gem_dir
  end

  def test_execute_keeps_older_versions_with_deps
    @b_1 = util_spec 'b', 1
    @b_2 = util_spec 'b', 2

    @c = util_spec 'c', 1 do |s|
      s.add_dependency 'b', '1'
    end

    install_gem @b_1
    install_gem @b_2
    install_gem @c

    @cmd.options[:args] = []

    @cmd.execute

    assert_path_exists @b_1.gem_dir
  end

  def test_execute_ignore_default_gem_verbose
    Gem.configuration.verbose = :really

    @b_1 = util_spec 'b', 1
    @b_default = new_default_spec "b", "2"
    @b_2 = util_spec 'b', 3

    install_gem @b_1
    install_default_specs @b_default
    install_gem @b_2

    @cmd.options[:args] = []

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{^Skipped default gems: b-2}, @ui.output
    assert_empty @ui.error
  end

  def test_execute_remove_gem_home_only
    c_1, = util_gem 'c', '1'
    c_2, = util_gem 'c', '2'
    d_1, = util_gem 'd', '1'
    d_2, = util_gem 'd', '2'
    e_1, = util_gem 'e', '1'
    e_2, = util_gem 'e', '2'

    c_1 = install_gem c_1, :user_install => true # pick up user install path
    c_2 = install_gem c_2

    d_1 = install_gem d_1
    d_2 = install_gem d_2, :user_install => true # pick up user install path

    e_1 = install_gem e_1
    e_2 = install_gem e_2

    Gem::Specification.dirs = [Gem.dir, Gem.user_dir]

    @cmd.options[:args] = []

    @cmd.execute

    assert_path_exists c_1.gem_dir
    refute_path_exists d_1.gem_dir
    refute_path_exists e_1.gem_dir
  end

  def test_execute_user_install
    c_1, = util_gem 'c', '1.0'
    c_2, = util_gem 'c', '1.1'

    d_1, = util_gem 'd', '1.0'
    d_2, = util_gem 'd', '1.1'

    c_1 = install_gem c_1, :user_install => true # pick up user install path
    c_2 = install_gem c_2, :user_install => true # pick up user install path

    d_1 = install_gem d_1
    d_2 = install_gem d_2

    Gem::Specification.dirs = [Gem.dir, Gem.user_dir]

    @cmd.handle_options %w[--user-install]
    @cmd.options[:args] = []

    @cmd.execute

    refute_path_exists c_1.gem_dir
    assert_path_exists c_2.gem_dir

    assert_path_exists d_1.gem_dir
    assert_path_exists d_2.gem_dir
  end

end
