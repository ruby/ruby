# frozen_string_literal: true
require_relative "installer_test_case"
require "rubygems/install_update_options"
require "rubygems/command"
require "rubygems/dependency_installer"

class TestGemInstallUpdateOptions < Gem::InstallerTestCase
  def setup
    super

    @cmd = Gem::Command.new "dummy", "dummy",
                            Gem::DependencyInstaller::DEFAULT_OPTIONS
    @cmd.extend Gem::InstallUpdateOptions
    @cmd.add_install_update_options
  end

  def test_add_install_update_options
    args = %w[
      --document
      --build-root build_root
      --format-exec
      --ignore-dependencies
      --document
      -E
      -f
      -i /install_to
      -w
      --post-install-message
    ]

    args.concat %w[--vendor] unless Gem.java_platform?

    args.concat %w[-P HighSecurity] if Gem::HAVE_OPENSSL

    assert @cmd.handles?(args)
  end

  def test_build_root
    @cmd.handle_options %w[--build-root build_root]

    assert_equal File.expand_path("build_root"), @cmd.options[:build_root]
  end

  def test_doc
    @cmd.handle_options %w[--doc]

    assert_equal %w[ri], @cmd.options[:document].sort
  end

  def test_doc_rdoc
    @cmd.handle_options %w[--doc=rdoc]

    assert_equal %w[rdoc], @cmd.options[:document]

    @cmd.handle_options %w[--doc ri]

    assert_equal %w[ri], @cmd.options[:document]
  end

  def test_doc_rdoc_ri
    @cmd.handle_options %w[--doc=rdoc,ri]

    assert_equal %w[rdoc ri], @cmd.options[:document]
  end

  def test_doc_no
    @cmd.handle_options %w[--no-doc]

    assert_equal [], @cmd.options[:document]
  end

  def test_document
    @cmd.handle_options %w[--document]

    assert_equal %w[ri], @cmd.options[:document].sort
  end

  def test_document_no
    @cmd.handle_options %w[--no-document]

    assert_equal %w[], @cmd.options[:document]
  end

  def test_document_rdoc
    @cmd.handle_options %w[--document=rdoc]

    assert_equal %w[rdoc], @cmd.options[:document]

    @cmd.handle_options %w[--document ri]

    assert_equal %w[ri], @cmd.options[:document]
  end

  def test_security_policy
    pend "openssl is missing" unless Gem::HAVE_OPENSSL

    @cmd.handle_options %w[-P HighSecurity]

    assert_equal Gem::Security::HighSecurity, @cmd.options[:security_policy]
  end

  def test_security_policy_unknown
    pend "openssl is missing" unless Gem::HAVE_OPENSSL

    @cmd.add_install_update_options

    e = assert_raise Gem::OptionParser::InvalidArgument do
      @cmd.handle_options %w[-P UnknownSecurity]
    end
    assert_includes e.message, "UnknownSecurity"
  end

  def test_user_install_enabled
    @spec = quick_gem "a" do |spec|
      util_make_exec spec
    end

    util_build_gem @spec
    @gem = @spec.cache_file

    @cmd.handle_options %w[--user-install]

    assert @cmd.options[:user_install]

    @installer = Gem::Installer.at @gem, @cmd.options
    @installer.install
    assert_path_exist File.join(Gem.user_dir, "gems")
    assert_path_exist File.join(Gem.user_dir, "gems", @spec.full_name)
  end

  def test_user_install_disabled_read_only
    @spec = quick_gem "a" do |spec|
      util_make_exec spec
    end

    util_build_gem @spec
    @gem = @spec.cache_file

    if win_platform?
      pend("test_user_install_disabled_read_only test skipped on MS Windows")
    elsif Process.uid.zero?
      pend("test_user_install_disabled_read_only test skipped in root privilege")
    else
      @cmd.handle_options %w[--no-user-install]

      refute @cmd.options[:user_install]

      FileUtils.chmod 0755, @userhome
      FileUtils.chmod 0000, @gemhome

      Gem.use_paths @gemhome, @userhome

      assert_raise(Gem::FilePermissionError) do
        Gem::Installer.at(@gem, @cmd.options).install
      end
    end
  ensure
    FileUtils.chmod 0755, @gemhome
  end

  def test_vendor
    vendordir(File.join(@tempdir, "vendor")) do
      @cmd.handle_options %w[--vendor]

      assert @cmd.options[:vendor]
      assert_equal Gem.vendor_dir, @cmd.options[:install_dir]
    end
  end

  def test_vendor_missing
    vendordir(nil) do
      e = assert_raise Gem::OptionParser::InvalidOption do
        @cmd.handle_options %w[--vendor]
      end

      assert_equal "invalid option: --vendor your platform is not supported",
                   e.message

      refute @cmd.options[:vendor]
      refute @cmd.options[:install_dir]
    end
  end

  def test_post_install_message_no
    @cmd.handle_options %w[--no-post-install-message]

    assert_equal false, @cmd.options[:post_install_message]
  end

  def test_post_install_message
    @cmd.handle_options %w[--post-install-message]

    assert_equal true, @cmd.options[:post_install_message]
  end

  def test_minimal_deps_no
    @cmd.handle_options %w[--no-minimal-deps]

    assert_equal false, @cmd.options[:minimal_deps]
  end

  def test_minimal_deps
    @cmd.handle_options %w[--minimal-deps]

    assert_equal true, @cmd.options[:minimal_deps]
  end
end
