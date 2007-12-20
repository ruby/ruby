require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/install_update_options'
require 'rubygems/command'

class TestGemInstallUpdateOptions < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Command.new 'dummy', 'dummy'
    @cmd.extend Gem::InstallUpdateOptions
  end

  def test_add_install_update_options
    @cmd.add_install_update_options

    args = %w[-i /install_to --rdoc --ri -E -f -t -w -P HighSecurity
              --ignore-dependencies --format-exec --include-dependencies]

    assert @cmd.handles?(args)
  end

  def test_security_policy
    @cmd.add_install_update_options

    @cmd.handle_options %w[-P HighSecurity]

    assert_equal Gem::Security::HighSecurity, @cmd.options[:security_policy]
  end

  def test_security_policy_unknown
    @cmd.add_install_update_options

    assert_raise OptionParser::InvalidArgument do
      @cmd.handle_options %w[-P UnknownSecurity]
    end
  end

end
