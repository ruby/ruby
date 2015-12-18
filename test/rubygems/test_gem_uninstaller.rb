# frozen_string_literal: false
require 'rubygems/installer_test_case'
require 'rubygems/uninstaller'

class TestGemUninstaller < Gem::InstallerTestCase

  def setup
    super
    common_installer_setup

    build_rake_in do
      use_ui ui do
        @installer.install
        @spec = @installer.spec

        @user_installer.install
        @user_spec = @user_installer.spec
      end
    end

    Gem::Specification.reset
  end

  def test_initialize_expand_path
    uninstaller = Gem::Uninstaller.new nil, :install_dir => '/foo//bar'

    assert_match %r|/foo/bar$|, uninstaller.instance_variable_get(:@gem_home)
  end

  def test_ask_if_ok
    c = util_spec 'c'

    uninstaller = Gem::Uninstaller.new nil

    ok = :junk

    ui = Gem::MockGemUi.new "\n"

    use_ui ui do
      ok = uninstaller.ask_if_ok c
    end

    refute ok
  end

  def test_remove_all
    uninstaller = Gem::Uninstaller.new nil

    ui = Gem::MockGemUi.new "y\n"

    use_ui ui do
      uninstaller.remove_all [@spec]
    end

    refute_path_exists @spec.gem_dir
  end

  def test_remove_executables_force_keep
    uninstaller = Gem::Uninstaller.new nil, :executables => false

    executable = File.join Gem.bindir(@user_spec.base_dir), 'executable'
    assert File.exist?(executable), 'executable not written'

    use_ui @ui do
      uninstaller.remove_executables @user_spec
    end

    assert File.exist? executable

    assert_equal "Executables and scripts will remain installed.\n", @ui.output
  end

  def test_remove_executables_force_remove
    uninstaller = Gem::Uninstaller.new nil, :executables => true

    executable = File.join Gem.bindir(@user_spec.base_dir), 'executable'
    assert File.exist?(executable), 'executable not written'

    use_ui @ui do
      uninstaller.remove_executables @user_spec
    end

    assert_equal "Removing executable\n", @ui.output

    refute File.exist? executable
  end

  def test_remove_executables_user
    uninstaller = Gem::Uninstaller.new nil, :executables => true

    use_ui @ui do
      uninstaller.remove_executables @user_spec
    end

    exec_path = File.join Gem.user_dir, 'bin', 'executable'
    refute File.exist?(exec_path), 'exec still exists in user bin dir'

    assert_equal "Removing executable\n", @ui.output
  end

  def test_remove_executables_user_format
    Gem::Installer.exec_format = 'foo-%s-bar'

    uninstaller = Gem::Uninstaller.new nil, :executables => true, :format_executable => true

    use_ui @ui do
      uninstaller.remove_executables @user_spec
    end

    exec_path = File.join Gem.user_dir, 'bin', 'foo-executable-bar'
    assert_equal false, File.exist?(exec_path), 'removed exec from bin dir'

    assert_equal "Removing foo-executable-bar\n", @ui.output
  ensure
    Gem::Installer.exec_format = nil
  end

  def test_remove_executables_user_format_disabled
    Gem::Installer.exec_format = 'foo-%s-bar'

    uninstaller = Gem::Uninstaller.new nil, :executables => true

    use_ui @ui do
      uninstaller.remove_executables @user_spec
    end

    exec_path = File.join Gem.user_dir, 'bin', 'executable'
    refute File.exist?(exec_path), 'removed exec from bin dir'

    assert_equal "Removing executable\n", @ui.output
  ensure
    Gem::Installer.exec_format = nil
  end

  def test_remove_not_in_home
    uninstaller = Gem::Uninstaller.new nil, :install_dir => "#{@gemhome}2"

    e = assert_raises Gem::GemNotInHomeException do
      use_ui ui do
        uninstaller.remove @spec
      end
    end

    expected =
      "Gem '#{@spec.full_name}' is not installed in directory #{@gemhome}2"

    assert_equal expected, e.message

    assert_path_exists @spec.gem_dir
  end

  def test_path_ok_eh
    uninstaller = Gem::Uninstaller.new nil

    assert_equal true, uninstaller.path_ok?(@gemhome, @spec)
  end

  def test_path_ok_eh_legacy
    uninstaller = Gem::Uninstaller.new nil

    @spec.loaded_from = @spec.loaded_from.gsub @spec.full_name, '\&-legacy'
    @spec.internal_init # blow out cache. but why did ^^ depend on cache?
    @spec.platform = 'legacy'

    assert_equal true, uninstaller.path_ok?(@gemhome, @spec)
  end

  def test_path_ok_eh_user
    uninstaller = Gem::Uninstaller.new nil

    assert_equal true, uninstaller.path_ok?(Gem.user_dir, @user_spec)
  end

  def test_uninstall
    uninstaller = Gem::Uninstaller.new @spec.name, :executables => true

    gem_dir = File.join @gemhome, 'gems', @spec.full_name

    Gem.pre_uninstall do
      assert File.exist?(gem_dir), 'gem_dir should exist'
    end

    Gem.post_uninstall do
      refute File.exist?(gem_dir), 'gem_dir should not exist'
    end

    uninstaller.uninstall

    refute File.exist?(gem_dir)

    assert_same uninstaller, @pre_uninstall_hook_arg
    assert_same uninstaller, @post_uninstall_hook_arg
  end

  def test_uninstall_default_gem
    spec = new_default_spec 'default', '2'

    install_default_gems spec

    uninstaller = Gem::Uninstaller.new spec.name, :executables => true

    e = assert_raises Gem::InstallError do
      uninstaller.uninstall
    end

    assert_equal 'gem "default" cannot be uninstalled ' +
                 'because it is a default gem',
                 e.message
  end

  def test_uninstall_default_gem_with_same_version
    default_spec = new_default_spec 'default', '2'
    install_default_gems default_spec

    spec = new_spec 'default', '2'
    install_gem spec

    Gem::Specification.reset

    uninstaller = Gem::Uninstaller.new spec.name, :executables => true

    uninstaller.uninstall

    refute_path_exists spec.gem_dir
  end

  def test_uninstall_extension
    @spec.extensions << 'extconf.rb'
    write_file File.join(@tempdir, 'extconf.rb') do |io|
      io.write <<-RUBY
require 'mkmf'
create_makefile '#{@spec.name}'
      RUBY
    end

    @spec.files += %w[extconf.rb]

    use_ui @ui do
      path = Gem::Package.build @spec

      installer = Gem::Installer.at path
      installer.install
    end

    assert_path_exists @spec.extension_dir, 'sanity check'

    uninstaller = Gem::Uninstaller.new @spec.name, :executables => true
    uninstaller.uninstall

    refute_path_exists @spec.extension_dir
  end

  def test_uninstall_nonexistent
    uninstaller = Gem::Uninstaller.new 'bogus', :executables => true

    e = assert_raises Gem::InstallError do
      uninstaller.uninstall
    end

    assert_equal 'gem "bogus" is not installed', e.message
  end

  def test_uninstall_not_ok
    quick_gem 'z' do |s|
      s.add_runtime_dependency @spec.name
    end

    uninstaller = Gem::Uninstaller.new @spec.name

    gem_dir = File.join @gemhome, 'gems', @spec.full_name
    executable = File.join @gemhome, 'bin', 'executable'

    assert File.exist?(gem_dir),    'gem_dir must exist'
    assert File.exist?(executable), 'executable must exist'

    ui = Gem::MockGemUi.new "n\n"

    assert_raises Gem::DependencyRemovalException do
      use_ui ui do
        uninstaller.uninstall
      end
    end

    assert File.exist?(gem_dir),    'gem_dir must still exist'
    assert File.exist?(executable), 'executable must still exist'
  end

  def test_uninstall_user_install
    @user_spec = Gem::Specification.find_by_name 'b'

    uninstaller = Gem::Uninstaller.new(@user_spec.name,
                                       :executables  => true,
                                       :user_install => true)

    gem_dir = File.join @user_spec.gem_dir

    Gem.pre_uninstall do
      assert_path_exists gem_dir
    end

    Gem.post_uninstall do
      refute_path_exists gem_dir
    end

    uninstaller.uninstall

    refute_path_exists gem_dir

    assert_same uninstaller, @pre_uninstall_hook_arg
    assert_same uninstaller, @post_uninstall_hook_arg
  end

  def test_uninstall_wrong_repo
    Gem.use_paths "#{@gemhome}2", [@gemhome]

    uninstaller = Gem::Uninstaller.new @spec.name, :executables => true

    e = assert_raises Gem::InstallError do
      uninstaller.uninstall
    end

    expected = <<-MESSAGE.strip
#{@spec.name} is not installed in GEM_HOME, try:
\tgem uninstall -i #{@gemhome} a
    MESSAGE

    assert_equal expected, e.message
  end

  def test_uninstall_selection
    util_make_gems

    list = Gem::Specification.find_all_by_name 'a'

    uninstaller = Gem::Uninstaller.new 'a'

    ui = Gem::MockGemUi.new "1\ny\n"

    use_ui ui do
      uninstaller.uninstall
    end

    updated_list = Gem::Specification.find_all_by_name('a')
    assert_equal list.length - 1, updated_list.length

    assert_match ' 1. a-1',          ui.output
    assert_match ' 2. a-2',          ui.output
    assert_match ' 3. a-3.a',        ui.output
    assert_match ' 4. All versions', ui.output
    assert_match 'uninstalled a-1',  ui.output
  end

  def test_uninstall_selection_greater_than_one
    util_make_gems

    list = Gem::Specification.find_all_by_name('a')

    uninstaller = Gem::Uninstaller.new('a')

    use_ui Gem::MockGemUi.new("2\ny\n") do
      uninstaller.uninstall
    end

    updated_list = Gem::Specification.find_all_by_name('a')
    assert_equal list.length - 1, updated_list.length
  end

  def test_uninstall_prompts_about_broken_deps
    quick_gem 'r', '1' do |s| s.add_dependency 'q', '= 1' end
    quick_gem 'q', '1'

    un = Gem::Uninstaller.new('q')
    ui = Gem::MockGemUi.new("y\n")

    use_ui ui do
      un.uninstall
    end

    lines = ui.output.split("\n")
    lines.shift

    assert_match %r!You have requested to uninstall the gem:!, lines.shift
    lines.shift
    lines.shift

    assert_match %r!r-1 depends on q \(= 1\)!, lines.shift
    assert_match %r!Successfully uninstalled q-1!, lines.last
  end

  def test_uninstall_only_lists_unsatisfied_deps
    quick_gem 'r', '1' do |s| s.add_dependency 'q', '~> 1.0' end
    quick_gem 'x', '1' do |s| s.add_dependency 'q', '= 1.0'  end
    quick_gem 'q', '1.0'
    quick_gem 'q', '1.1'

    un = Gem::Uninstaller.new('q', :version => "1.0")
    ui = Gem::MockGemUi.new("y\n")

    use_ui ui do
      un.uninstall
    end

    lines = ui.output.split("\n")
    lines.shift

    assert_match %r!You have requested to uninstall the gem:!, lines.shift
    lines.shift
    lines.shift

    assert_match %r!x-1 depends on q \(= 1.0\)!, lines.shift
    assert_match %r!Successfully uninstalled q-1.0!, lines.last
  end

  def test_uninstall_doesnt_prompt_when_other_gem_satisfies_requirement
    quick_gem 'r', '1' do |s| s.add_dependency 'q', '~> 1.0' end
    quick_gem 'q', '1.0'
    quick_gem 'q', '1.1'

    un = Gem::Uninstaller.new('q', :version => "1.0")
    ui = Gem::MockGemUi.new("y\n")

    use_ui ui do
      un.uninstall
    end

    lines = ui.output.split("\n")

    assert_equal "Successfully uninstalled q-1.0", lines.shift
  end

  def test_uninstall_doesnt_prompt_when_removing_a_dev_dep
    quick_gem 'r', '1' do |s| s.add_development_dependency 'q', '= 1.0' end
    quick_gem 'q', '1.0'

    un = Gem::Uninstaller.new('q', :version => "1.0")
    ui = Gem::MockGemUi.new("y\n")

    use_ui ui do
      un.uninstall
    end

    lines = ui.output.split("\n")

    assert_equal "Successfully uninstalled q-1.0", lines.shift
  end

  def test_uninstall_doesnt_prompt_and_raises_when_abort_on_dependent_set
    quick_gem 'r', '1' do |s| s.add_dependency 'q', '= 1' end
    quick_gem 'q', '1'

    un = Gem::Uninstaller.new('q', :abort_on_dependent => true)
    ui = Gem::MockGemUi.new("y\n")

    assert_raises Gem::DependencyRemovalException do
      use_ui ui do
        un.uninstall
      end
    end
  end

  def test_uninstall_prompt_includes_dep_type
    quick_gem 'r', '1' do |s|
      s.add_development_dependency 'q', '= 1'
    end

    quick_gem 'q', '1'

    un = Gem::Uninstaller.new('q', :check_dev => true)
    ui = Gem::MockGemUi.new("y\n")

    use_ui ui do
      un.uninstall
    end

    lines = ui.output.split("\n")
    lines.shift

    assert_match %r!You have requested to uninstall the gem:!, lines.shift
    lines.shift
    lines.shift

    assert_match %r!r-1 depends on q \(= 1, development\)!, lines.shift
    assert_match %r!Successfully uninstalled q-1!, lines.last
  end
end
