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
    @days = days.to_i
    @now = now
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
end
