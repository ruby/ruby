# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/signout_command"
require "rubygems/installer"

class TestGemCommandsSignoutCommand < Gem::TestCase
  def setup
    super
    @cmd = Gem::Commands::SignoutCommand.new
  end

  def test_execute_when_user_is_signed_in
    FileUtils.mkdir_p File.dirname(Gem.configuration.credentials_path)
    FileUtils::touch Gem.configuration.credentials_path

    @sign_out_ui = Gem::MockGemUi.new
    use_ui(@sign_out_ui) { @cmd.execute }

    assert_match %r{You have successfully signed out}, @sign_out_ui.output
    assert_equal false, File.exist?(Gem.configuration.credentials_path)
  end

  def test_execute_when_not_signed_in # i.e. no credential file created
    @sign_out_ui = Gem::MockGemUi.new
    use_ui(@sign_out_ui) { @cmd.execute }

    assert_match %r{You are not currently signed in}, @sign_out_ui.error
  end
end
