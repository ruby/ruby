######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems/installer_test_case'
require 'rubygems/uninstaller'

class TestGemUninstaller < Gem::InstallerTestCase

  def setup
    super

    @user_spec.executables = ["executable"]

    # HACK util_make_exec
    user_bin_dir = File.join Gem.user_dir, 'gems', @user_spec.full_name, 'bin'
    FileUtils.mkdir_p user_bin_dir
    exec_path = File.join user_bin_dir, "executable"
    open exec_path, 'w' do |f|
      f.puts "#!/usr/bin/ruby"
    end

    user_bin_dir = File.join Gem.user_dir, 'bin'
    FileUtils.mkdir_p user_bin_dir
    exec_path = File.join user_bin_dir, "executable"
    open exec_path, 'w' do |f|
      f.puts "#!/usr/bin/ruby"
    end

    build_rake_in do
      use_ui ui do
        @installer.install
        @user_installer.install
        Gem::Uninstaller.new(@user_spec.name, :executables => false).uninstall
      end
    end
  end

  def test_initialize_expand_path
    uninstaller = Gem::Uninstaller.new nil, :install_dir => '/foo//bar'

    assert_match %r|/foo/bar$|, uninstaller.instance_variable_get(:@gem_home)
  end

  def test_remove_executables_force_keep
    uninstaller = Gem::Uninstaller.new nil, :executables => false

    executable = File.join Gem.user_dir, 'bin', 'executable'
    assert File.exist?(executable), 'executable not written'

    use_ui @ui do
      uninstaller.remove_executables @user_spec
    end

    assert File.exist? executable

    assert_equal "Executables and scripts will remain installed.\n", @ui.output
  end

  def test_remove_executables_force_remove
    uninstaller = Gem::Uninstaller.new nil, :executables => true

    executable = File.join Gem.user_dir, 'bin', 'executable'
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
    assert_equal false, File.exist?(exec_path), 'removed exec from bin dir'

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

    assert_equal "Removing executable\n", @ui.output
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
    assert_equal false, File.exist?(exec_path), 'removed exec from bin dir'

    assert_equal "Removing executable\n", @ui.output
  ensure
    Gem::Installer.exec_format = nil
  end


  def test_path_ok_eh
    uninstaller = Gem::Uninstaller.new nil

    assert_equal true, uninstaller.path_ok?(@gemhome, @spec)
  end

  def test_path_ok_eh_legacy
    uninstaller = Gem::Uninstaller.new nil

    @spec.loaded_from.gsub! @spec.full_name, '\&-legacy'
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

  def test_uninstall_user
    uninstaller = Gem::Uninstaller.new @user_spec.name, :executables => true,
                  :user_install => true

    gem_dir = File.join Gem.user_dir, 'gems', @user_spec.full_name

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

end

