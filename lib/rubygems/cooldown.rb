# frozen_string_literal: true

require_relative "cooldown_settings"
require_relative "user_interaction"

##
# Applies a cooldown period to remote gem versions as a supply chain attack
# mitigation.  When a cooldown of N days is configured, gem versions
# published within the last N days are not considered for installation or
# update.  Versions whose publish time is unknown are never excluded, so
# sources that do not provide publish times keep working.
#
# The cooldown period comes from the <tt>--cooldown DAYS</tt> option when
# given, and 0 there disables the cooldown.  Without the option the
# <tt>:cooldown:</tt> setting in the gemrc file and Bundler's own cooldown
# setting both apply and the longer of the two wins, so a 0 in either of them
# disables nothing while the other names a period.

class Gem::Cooldown
  ##
  # The cooldown period in days.

  attr_reader :days

  ##
  # Creates a Cooldown from the command line +options+.  The --cooldown
  # option wins outright, so <tt>--cooldown 0</tt> bypasses the cooldown
  # however the two tools are configured.  Without it the :cooldown: gemrc
  # setting and Bundler's cooldown setting are both read and the longer of
  # the two applies, so a cooldown configured for only one of them still
  # covers gem commands.

  def self.from_options(options)
    days = options[:cooldown]
    return new(days) unless days.nil?

    require_relative "bundler_settings"

    new Gem::CooldownSettings.combine(warn_unless_valid(Gem.configuration.cooldown, "the gemrc file"),
                                      warn_unless_valid(Gem::BundlerSettings["cooldown"], "Bundler's configuration"))
  end

  def initialize(days, now: Time.now)
    invalid = Gem::CooldownSettings.invalid?(days)

    @days = Gem::CooldownSettings.days(days) || 0
    @now = now

    Gem::Cooldown.warn_invalid_days(days, "the cooldown setting") if invalid
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

  # Returns +value+, warning first when it is configured but cannot be read
  # as a number of days.

  def self.warn_unless_valid(value, source) # :nodoc:
    warn_invalid_days(value, source) if Gem::CooldownSettings.invalid?(value)

    value
  end

  # Warns that a configured cooldown value cannot be read as a non-negative
  # integer, so it does not apply.  The --cooldown option is validated by the
  # option parser; this catches the config file paths.  Both the gemrc and
  # Bundler settings feed one resolution, so each source gets its own warning
  # rather than the first one silencing the other.

  def self.warn_invalid_days(value, source) # :nodoc:
    @warned_invalid_days ||= []
    return if @warned_invalid_days.include?(source)
    @warned_invalid_days << source

    Gem::DefaultUserInteraction.ui.alert_warning Gem::CooldownSettings.invalid_message(value, source)
  end

  def self.reset_warned_invalid_days # :nodoc:
    @warned_invalid_days = nil
  end
end
