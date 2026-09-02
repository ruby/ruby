# frozen_string_literal: true

require_relative "user_interaction"

##
# Applies a cooldown period to remote gem versions as a supply chain attack
# mitigation.  When a cooldown of N days is configured, gem versions
# published within the last N days are not considered for installation or
# update.  Versions whose publish time is unknown are never excluded, so
# sources that do not provide publish times keep working.
#
# The cooldown period comes from the <tt>--cooldown DAYS</tt> option when
# given, falling back to the <tt>:cooldown:</tt> setting in the gemrc file.
# A value of 0 disables the cooldown.

class Gem::Cooldown
  ##
  # The cooldown period in days.

  attr_reader :days

  ##
  # Creates a Cooldown from the command line +options+, preferring the
  # --cooldown option over the :cooldown: gemrc setting.

  def self.from_options(options)
    new(options[:cooldown] || Gem.configuration.cooldown)
  end

  def initialize(days, now: Time.now)
    # A gemrc value is arbitrary YAML, so it can be any type at all. Anything
    # that cannot be read as a non-negative integer leaves the cooldown
    # disabled rather than raising out of an unrelated command.
    valid = valid_days?(days)

    @days = valid ? days.to_i : 0
    @now = now

    Gem::Cooldown.warn_invalid_days(days) unless valid || days.nil?
  end

  ##
  # True when a cooldown period is configured.

  def active?
    @days > 0
  end

  ##
  # True when a gem version published at +created_at+ must not be
  # considered.  Versions with an unknown publish time (+nil+) are kept.

  def skip?(created_at)
    return false unless active?
    return false unless created_at

    (@now - created_at) < @days * 86_400
  end

  ##
  # Number of days until a gem version published at +created_at+ leaves
  # the cooldown period, rounded up and at least 1.

  def remaining_days(created_at)
    remaining = @days * 86_400 - (@now - created_at)

    [(remaining / 86_400.0).ceil, 1].max
  end

  ##
  # Reports, per gem, the newest version the cooldown kept out of a
  # completed installation or update.  +entries+ are hashes with :name,
  # :version, :resolved and :available_in_days keys; when several entries
  # name the same gem only the newest version is shown.

  def self.output_skipped_summary(entries)
    return if entries.nil? || entries.empty?

    newest = {}
    entries.each do |entry|
      current = newest[entry[:name]]
      newest[entry[:name]] = entry if current.nil? || entry[:version] > current[:version]
    end

    ui = Gem::DefaultUserInteraction.ui
    ui.say "The following gem versions were skipped by the cooldown setting:"
    newest.values.sort_by {|entry| entry[:name] }.each do |entry|
      days = entry[:available_in_days]
      ui.say "  * #{entry[:name]} #{entry[:version]} (available in #{days} #{days == 1 ? "day" : "days"}), resolved #{entry[:resolved]} instead"
    end
  end

  # Matches an ISO 8601 time zone designator at the end of a timestamp.
  TIME_ZONE_SUFFIX = /(?:Z|z|[+-]\d{2}(?::?\d{2})?)\z/ # :nodoc:
  private_constant :TIME_ZONE_SUFFIX

  # Matches the four-digit year an ISO 8601 timestamp starts with.
  # Time.iso8601 also accepts a year of any length, and one far enough
  # away overflows the Float arithmetic behind #remaining_days.
  FOUR_DIGIT_YEAR = /\A\d{4}-/ # :nodoc:
  private_constant :FOUR_DIGIT_YEAR

  ##
  # Parses a +created_at+ timestamp from the compact index.  A timestamp
  # without a time zone offset is read as UTC, because reading it as local
  # time would shift the cooldown window by the environment's offset.
  # Returns nil for anything unparsable, including a year outside four
  # digits, so the cooldown fails open.

  def self.parse_created_at(value)
    return unless value.is_a?(String) && value.match?(FOUR_DIGIT_YEAR)

    require "time"
    begin
      Time.iso8601(value.match?(TIME_ZONE_SUFFIX) ? value : "#{value}Z")
    rescue ArgumentError
      nil
    end
  end

  ##
  # Warns once per process that +source+ did not provide publish times, so
  # the cooldown cannot be applied to gems from it.

  def self.warn_missing_created_at(source)
    return if @warned
    @warned = true

    Gem::DefaultUserInteraction.ui.alert_warning \
      "#{source.uri} does not provide gem publish times, the cooldown period does not apply to gems from this source"
  end

  def self.reset_warned_missing_created_at # :nodoc:
    @warned = nil
  end

  # Warns once per process that a configured cooldown value cannot be read
  # as a non-negative integer, which leaves the cooldown disabled.  The
  # --cooldown option is validated by the option parser; this catches the
  # gemrc path.

  def self.warn_invalid_days(value) # :nodoc:
    return if @warned_invalid_days
    @warned_invalid_days = true

    Gem::DefaultUserInteraction.ui.alert_warning \
      "Invalid cooldown value #{value.inspect}, so the cooldown is disabled. " \
      "Expected a non-negative integer number of days."
  end

  def self.reset_warned_invalid_days # :nodoc:
    @warned_invalid_days = nil
  end

  private

  def valid_days?(value)
    days = Integer(value.to_s, exception: false)

    !days.nil? && !days.negative?
  end
end
