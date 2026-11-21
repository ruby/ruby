# frozen_string_literal: true

require_relative "../command"

class Gem::Commands::SignoutCommand < Gem::Command
  def initialize
    super "signout", "Sign out from all the current sessions."
  end

  def description # :nodoc:
    "The `signout` command is used to sign out from all current sessions,"\
    " allowing you to sign in using a different set of credentials. It removes"\
    " the ~/.gem/credentials file. If the :credential_store: gemrc option is"\
    " set, it also removes every RubyGems key from the credential store,"\
    " including keys saved for other hosts with `gem signin --host`."
  end

  def usage # :nodoc:
    program_name
  end

  def execute
    credentials_path = Gem.configuration.credentials_path
    credentials_file_exists = File.exist?(credentials_path)

    if !credentials_file_exists && !Gem.configuration.credential_store
      alert_error "You are not currently signed in."
      return
    end

    # An unwritable file must not leave the stored keys behind, so each half
    # reports its own outcome.
    store_cleared, file_removed = Gem.configuration.unset_api_key!

    unremoved = []
    unremoved << "the credential store" unless store_cleared
    unremoved << "'#{credentials_path}'" if credentials_file_exists && !file_removed

    unless unremoved.empty?
      alert_error "Could not remove the credentials from #{unremoved.join(" and ")}." \
                  " They are still there. Check that the file and its directory are writable," \
                  " or remove them yourself to finish signing out."
      terminate_interaction 1
    end

    if Gem.configuration.credential_store
      say "You have successfully signed out of every registry, including RubyGems.org."
    else
      say "You have successfully signed out from all sessions."
    end
  end
end
