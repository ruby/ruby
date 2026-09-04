# frozen_string_literal: true

# Skip reloading when an identical copy (e.g. the one shipped inside the Bundler
# gem) was already required from a different path, to avoid redefinition warnings.
return if defined?(Gem::CooldownSettings)

##
# The rules RubyGems and Bundler share for reading a configured cooldown
# period.  Bundler ships a copy of this file, so it deliberately has no
# requires: none of the rest of RubyGems is guaranteed to be around it.

module Gem::CooldownSettings
  ##
  # +value+ read as a number of days, or nil when it is absent or cannot be
  # read as a non-negative integer.  A gemrc entry and a Bundler config entry
  # are both arbitrary YAML, so either can be any type at all.

  def self.days(value)
    return if value.nil?

    # Base 10 explicitly: a leading zero is how a user writes a small number
    # of days, not a request for octal.
    days = Integer(value.to_s, 10, exception: false)

    days if days && !days.negative?
  end

  ##
  # True when +value+ is configured but cannot be read as a number of days.

  def self.invalid?(value)
    !value.nil? && days(value).nil?
  end

  ##
  # The cooldown that applies when RubyGems and Bundler are configured
  # separately: the longest of +values+, so a cooldown configured for only
  # one of the two tools protects both.  Returns nil when none of them is
  # usable.
  #
  # A configured 0 takes part like any other value rather than switching the
  # cooldown off, which leaves <tt>--cooldown 0</tt> as the way to bypass a
  # cooldown that the other tool configures.

  def self.combine(*values)
    values.filter_map {|value| days(value) }.max
  end

  # +source+ names where the value came from, since RubyGems and Bundler now
  # each read the other's setting and the same complaint from either of them
  # is otherwise impossible to trace back to a file.

  def self.invalid_message(value, source) # :nodoc:
    "Invalid cooldown value #{value.inspect} in #{source}, so it is ignored. " \
      "Expected a non-negative integer number of days."
  end
end
