# frozen_string_literal: true

require "rbconfig"

module Gem
  ##
  # An Array of Regexps that match windows Ruby platforms.

  WIN_PATTERNS = [
    /bccwin/i,
    /cygwin/i,
    /djgpp/i,
    /mingw/i,
    /mswin/i,
    /wince/i,
  ].freeze

  @@win_platform = nil

  ##
  # Is this a windows platform?

  def self.win_platform?
    if @@win_platform.nil?
      ruby_platform = RbConfig::CONFIG["host_os"]
      @@win_platform = !WIN_PATTERNS.find {|r| ruby_platform =~ r }.nil?
    end

    @@win_platform
  end
end
