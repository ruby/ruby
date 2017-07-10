require 'rubygems'

module BundlerVendoredPostIt::PostIt
  class Parser
    def initialize(file)
      @file = file
    end

    BUNDLED_WITH =
      /\n\nBUNDLED WITH\n\s{2,}(#{Gem::Version::VERSION_PATTERN})\n/

    def parse
      return unless lockfile = File.file?(@file) && File.read(@file)
      if lockfile =~ BUNDLED_WITH
        Regexp.last_match(1)
      else
        '< 1.10'
      end
    end
  end
end
