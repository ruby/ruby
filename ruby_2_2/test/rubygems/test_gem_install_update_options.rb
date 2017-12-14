require 'rubygems/installer_test_case'
require 'rubygems/install_update_options'
require 'rubygems/command'
require 'rubygems/dependency_installer'

class TestGemInstallUpdateOptions < Gem::InstallerTestCase

  def setup
    super

    @cmd = Gem::Command.new 'dummy', 'dummy',
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
      --rdoc
      --ri
      -E
      -f
      -i /install_to
      -w
      --vendor
    ]

    args.concat %w[-P HighSecurity] if defined?(OpenSSL::SSL)

    assert @cmd.handles?(args)
  end

  def test_build_root
    @cmd.handle_options %w[--build-root build_root]

    assert_equal File.expand_path('build_root'), @cmd.options[:build_root]
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

  def test_rdoc
    @cmd.handle_options %w[--rdoc]

    assert_equal %w[rdoc ri], @cmd.options[:document].sort
  end

  def test_rdoc_no
    @cmd.handle_options %w[--no-rdoc]

    assert_equal %w[ri], @cmd.options[:document]
  end

  def test_ri
    @cmd.handle_options %w[--no-ri]

    assert_equal %w[], @cmd.options[:document]
  end

  def test_security_policy
    skip 'openssl is missing' unless defined?(OpenSSL::SSL)

    @cmd.handle_options %w[-P HighSecurity]

    assert_equal Gem::Security::HighSecurity, @cmd.options[:security_policy]
  end

  def test_security_policy_unknown
    @cmd.add_install_update_options

    assert_raises OptionParser::InvalidArgument do
      @cmd.handle_options %w[-P UnknownSecurity]
    end
  end

  def test_user_install_enabled
    @cmd.handle_options %w[--user-install]

    assert @cmd.options[:user_install]

    @installer = Gem::Installer.new @gem, @cmd.options
    @installer.install
    assert_path_exists File.join(Gem.user_dir, 'gems')
    assert_path_exists File.join(Gem.user_dir, 'gems', @spec.full_name)
  end

  def test_user_install_disabled_read_only
    if win_platform?
      skip('test_user_install_disabled_read_only test skipped on MS Windows')
    else
      @cmd.handle_options %w[--no-user-install]

      refute @cmd.options[:user_install]

      FileUtils.chmod 0755, @userhome
      FileUtils.chmod 0000, @gemhome

      Gem.use_paths @gemhome, @userhome

      assert_raises(Gem::FilePermissionError) do
        Gem::Installer.new(@gem, @cmd.options).install
      end
    end
  ensure
    FileUtils.chmod 0755, @gemhome
  end

  def test_vendor
    @cmd.handle_options %w[--vendor]

    assert @cmd.options[:vendor]
    assert_equal Gem.vendor_dir, @cmd.options[:install_dir]
  end

  def test_vendor_missing
    orig_vendordir = RbConfig::CONFIG['vendordir']
    RbConfig::CONFIG.delete 'vendordir'

    e = assert_raises OptionParser::InvalidOption do
      @cmd.handle_options %w[--vendor]
    end

    assert_equal 'invalid option: --vendor your platform is not supported',
                 e.message

    refute @cmd.options[:vendor]
    refute @cmd.options[:install_dir]

  ensure
    RbConfig::CONFIG['vendordir'] = orig_vendordir
  end

end
