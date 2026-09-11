# frozen_string_literal: true

require_relative "../command"
require_relative "../cooldown"
require_relative "../cooldown_option"
require_relative "../local_remote_options"
require_relative "../spec_fetcher"
require_relative "../version_option"

class Gem::Commands::OutdatedCommand < Gem::Command
  include Gem::LocalRemoteOptions
  include Gem::VersionOption
  include Gem::CooldownOption

  def initialize
    super "outdated", "Display all gems that need updates"

    add_local_remote_options
    add_platform_option
    add_cooldown_option
  end

  def description # :nodoc:
    <<-EOF
The outdated command lists gems you may wish to upgrade to a newer version.

You can check for dependency mismatches using the dependency command and
update the gems with the update or install commands.
    EOF
  end

  def execute
    @cooldown = Gem::Cooldown.from_options options

    unless @cooldown.active?
      Gem::Specification.outdated_and_latest_version.each do |spec, remote_version|
        say "#{spec.name} (#{spec.version} < #{remote_version})"
      end

      return
    end

    execute_with_cooldown
  end

  private

  ##
  # Like Gem::Specification.outdated_and_latest_version, but the newest
  # version outside the cooldown period becomes the update candidate, and
  # newer versions still within the period are annotated.

  def execute_with_cooldown
    fetcher = Gem::SpecFetcher.fetcher

    Gem::Specification.latest_specs(true).each do |local_spec|
      dependency = Gem::Dependency.new local_spec.name, ">= #{local_spec.version}"

      # The :latest index carries only the newest version of each gem,
      # which leaves nothing to fall back to when the cooldown excludes
      # it, so search the full index instead.
      remotes, = fetcher.search_for_dependency dependency,
        type: dependency.prerelease? ? :complete : :released

      selectable, embargoed = partition_by_cooldown remotes

      candidate = selectable.max
      candidate = nil unless candidate && local_spec.version < candidate

      pending = embargoed.max
      pending = nil unless pending && local_spec.version < pending &&
                           (candidate.nil? || candidate < pending)

      next unless candidate || pending

      pending = "#{pending} (cooldown #{@cooldown.days}d)" if pending
      say "#{local_spec.name} (#{local_spec.version} < #{[candidate, pending].compact.join(", ")})"
    end
  end

  ##
  # Splits [NameTuple, Gem::Source] pairs into versions outside and within
  # the cooldown period.  Tuples with an unknown publish time count as
  # outside the period, so the cooldown fails open.

  def partition_by_cooldown(spec_tuples)
    selectable = []
    embargoed = []

    with_times = spec_tuples.map do |tup, source|
      [tup, source, source.created_at_for_tuple(tup)]
    end

    if !with_times.empty? && with_times.none? {|_, _, created_at| created_at }
      Gem::Cooldown.warn_missing_created_at with_times.first[1]
    end

    with_times.each do |tup, _, created_at|
      if @cooldown.skip?(created_at)
        embargoed << tup.version
      else
        selectable << tup.version
      end
    end

    [selectable, embargoed]
  end
end
