require 'json/common'
require 'json/pure/parser'
require 'json/pure/generator'

module JSON
  # Swap consecutive bytes of _string_ in place.
  def self.swap!(string) # :nodoc:
    0.upto(string.size / 2) do |i|
      break unless string[2 * i + 1]
      string[2 * i], string[2 * i + 1] = string[2 * i + 1], string[2 * i]
    end
    string
  end

  # This module holds all the modules/classes that implement JSON's
  # functionality in pure ruby.
  module Pure
    $DEBUG and warn "Using pure library for JSON."
    JSON.parser = Parser
    JSON.generator = Generator
  end
end
