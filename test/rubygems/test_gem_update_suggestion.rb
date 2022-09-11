# frozen_string_literal: true
require_relative "helper"
require "rubygems/command"
require "rubygems/update_suggestion"

class TestUpdateSuggestion < Gem::TestCase
  def setup
    super

    @cmd = Gem::Command.new "dummy", "dummy"
    @cmd.extend Gem::UpdateSuggestion
  end

  def with_eglible_environment(**params)
    self.class.with_eglible_environment(**params) do
      yield
    end
  end

  def self.with_eglible_environment(
    tty: true,
    rubygems_version: Gem::Version.new("1.2.3"),
    latest_rubygems_version: Gem::Version.new("2.0.0"),
    ci: false,
    cmd:
  )
    original_config, Gem.configuration[:prevent_update_suggestion] = Gem.configuration[:prevent_update_suggestion], nil
    original_env, ENV["RUBYGEMS_PREVENT_UPDATE_SUGGESTION"] = ENV["RUBYGEMS_PREVENT_UPDATE_SUGGESTION"], nil
    original_disable, Gem.disable_system_update_message = Gem.disable_system_update_message, nil
    Gem.configuration[:last_update_check] = nil

    Gem.ui.stub :tty?, tty do
      Gem.stub :rubygems_version, rubygems_version do
        Gem.stub :latest_rubygems_version, latest_rubygems_version do
          cmd.stub :ci?, ci do
            yield
          end
        end
      end
    end
  ensure
    Gem.configuration[:prevent_update_suggestion] = original_config
    ENV["RUBYGEMS_PREVENT_UPDATE_SUGGESTION"] = original_env
    Gem.disable_system_update_message = original_disable
  end

  def test_update_suggestion
    Gem.stub :rubygems_version, Gem::Version.new("1.2.3") do
      Gem.stub :latest_rubygems_version, Gem::Version.new("2.0.0") do
        assert_equal @cmd.update_suggestion, <<~SUGGESTION

          A new release of RubyGems is available: 1.2.3 → 2.0.0!
          Run `gem update --system 2.0.0` to update your installation.

        SUGGESTION
      end
    end
  end

  def test_eglible_for_update
    with_eglible_environment(cmd: @cmd) do
      Time.stub :now, 123456789 do
        assert @cmd.eglible_for_update?
        assert_equal Gem.configuration[:last_update_check], 123456789

        # test last check is written to config file
        assert File.read(Gem.configuration.config_file_name).match("last_update_check: 123456789")
      end
    end
  end

  def test_eglible_for_update_prevent_config
    with_eglible_environment(cmd: @cmd) do
      begin
        original_config, Gem.configuration[:prevent_update_suggestion] = Gem.configuration[:prevent_update_suggestion], true
        refute @cmd.eglible_for_update?
      ensure
        Gem.configuration[:prevent_update_suggestion] = original_config
      end
    end
  end

  def test_eglible_for_update_prevent_env
    with_eglible_environment(cmd: @cmd) do
      begin
        original_env, ENV["RUBYGEMS_PREVENT_UPDATE_SUGGESTION"] = ENV["RUBYGEMS_PREVENT_UPDATE_SUGGESTION"], "yes"
        refute @cmd.eglible_for_update?
      ensure
        ENV["RUBYGEMS_PREVENT_UPDATE_SUGGESTION"] = original_env
      end
    end
  end

  def test_eglible_for_update_non_tty
    with_eglible_environment(tty: false, cmd: @cmd) do
      refute @cmd.eglible_for_update?
    end
  end

  def test_eglible_for_update_for_prerelease
    with_eglible_environment(rubygems_version: Gem::Version.new("1.0.0-rc1"), cmd: @cmd) do
      refute @cmd.eglible_for_update?
    end
  end

  def test_eglible_for_update_disabled_update
    with_eglible_environment(cmd: @cmd) do
      begin
        original_disable, Gem.disable_system_update_message = Gem.disable_system_update_message, "disabled"
        refute @cmd.eglible_for_update?
      ensure
        Gem.disable_system_update_message = original_disable
      end
    end
  end

  def test_eglible_for_update_on_ci
    with_eglible_environment(ci: true, cmd: @cmd) do
      refute @cmd.eglible_for_update?
    end
  end

  def test_eglible_for_update_unwrittable_config
    with_eglible_environment(ci: true, cmd: @cmd) do
      Gem.configuration.stub :config_file_writable?, false do
        refute @cmd.eglible_for_update?
      end
    end
  end

  def test_eglible_for_update_notification_delay
    with_eglible_environment(cmd: @cmd) do
      Gem.configuration[:last_update_check] = Time.now.to_i
      refute @cmd.eglible_for_update?
    end
  end
end
