# frozen_string_literal: true
# :markup: markdown
# typed: ignore

#
module Prism
  module Translation
    case RUBY_VERSION
    when /^3\.3\./
      ParserCurrent = Parser33
    when /^3\.4\./
      ParserCurrent = Parser34
    when /^3\.5\./, /^4\.0\./
      ParserCurrent = Parser40
    when /^4\.1\./
      ParserCurrent = Parser41
    else
      # Keep this in sync with released Ruby.
      parser = Parser34
      major, minor, _patch = Gem::Version.new(RUBY_VERSION).segments
      warn "warning: `Prism::Translation::Current` is loading #{parser.name}, " \
           "but you are running #{major}.#{minor}."
      ParserCurrent = parser
    end
  end
end
