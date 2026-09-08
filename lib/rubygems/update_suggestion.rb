# frozen_string_literal: true

##
# Mixin methods for Gem::Command to promote available RubyGems update

module Gem::UpdateSuggestion
  ONE_WEEK = 7 * 24 * 60 * 60

  ##
  # Message to promote available RubyGems update with related gem update command.

  def update_suggestion
    current = Gem.rubygems_version
    latest = Gem.latest_rubygems_version

    <<-MESSAGE

A new release of RubyGems is available: #{current} → #{latest}!
See https://github.com/ruby/rubygems/blob/v#{latest}/CHANGELOG.md for the changes since #{current}.
Run `gem update --system #{latest}` to update your installation.

    MESSAGE
  end

  ##
  # Determines if current environment is eligible for update suggestion.

  def eligible_for_update?
    # explicit opt-out
    return false if Gem.configuration[:prevent_update_suggestion]
    return false if ENV["RUBYGEMS_PREVENT_UPDATE_SUGGESTION"]

    # focus only on human usage of final RubyGems releases
    return false unless Gem.ui.tty?
    return false if Gem.rubygems_version.prerelease?
    return false if Gem.disable_system_update_message
    return false if Gem::CIDetector.ci?

    # check makes sense only when we can store timestamp of last try
    # otherwise we will not be able to prevent "annoying" update message
    # on each command call
    return unless Gem.configuration.state_file_writable?

    # load time of last check, ensure the difference is enough to repeat the suggestion
    check_time = Time.now.to_i
    last_update_check = Gem.configuration.last_update_check
    return false if (check_time - last_update_check) < ONE_WEEK

    # compare current and latest version, this is the part where
    # latest rubygems spec is fetched from remote
    (Gem.rubygems_version < Gem.latest_rubygems_version).tap do |eligible|
      # store the time of last successful check into state file
      Gem.configuration.last_update_check = check_time

      return eligible
    end
  rescue StandardError # don't block install command on any problem
    false
  end
end
