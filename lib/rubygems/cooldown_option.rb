# frozen_string_literal: true

require_relative "cooldown"

##
# Mixin methods for the cooldown option for Gem::Commands.

module Gem::CooldownOption
  ##
  # Add the --cooldown option to the option parser.

  def add_cooldown_option(group = nil)
    args = [group, "--cooldown DAYS", Integer,
            "Do not use gem versions published within",
            "the last DAYS days (0 disables the cooldown)"].compact

    add_option(*args) do |value, options|
      if value.negative?
        raise Gem::OptionParser::InvalidArgument,
              "#{value} (expected a non-negative integer number of days; use 0 to disable the cooldown)"
      end

      options[:cooldown] = value
    end
  end
end
