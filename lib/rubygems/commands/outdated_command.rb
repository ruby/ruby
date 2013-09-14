require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/spec_fetcher'
require 'rubygems/version_option'

class Gem::Commands::OutdatedCommand < Gem::Command

  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def initialize
    super 'outdated', 'Display all gems that need updates'

    add_local_remote_options
    add_platform_option
  end

  def description # :nodoc:
    <<-EOF
The outdated command lists gems you way wish to upgrade to a newer version.

You can check for dependency mismatches using the dependency command and
update the gems with the update or install commands.
    EOF
  end

  def execute
    Gem::Specification.outdated_and_latest_version.each do |spec, remote_version|
      say "#{spec.name} (#{spec.version} < #{remote_version})"
    end
  end
end
