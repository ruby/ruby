# frozen_string_literal: true

require "rbconfig"

module Bundler
  WINDOWS = RbConfig::CONFIG["host_os"] =~ /(msdos|mswin|djgpp|mingw)/
  FREEBSD = RbConfig::CONFIG["host_os"].to_s.include?("bsd")
  NULL    = File::NULL
end
