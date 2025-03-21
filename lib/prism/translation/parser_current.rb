# frozen_string_literal: true
# typed: ignore

module Prism
  module Translation
    case RUBY_VERSION
    when /^3\.3\./
      ParserCurrent = Parser33
    when /^3\.4\./
      ParserCurrent = Parser34
    when /^3\.5\./
      ParserCurrent = Parser35
    else
      # Keep this in sync with released Ruby.
      parser = Parser34
      warn "warning: `Prism::Translation::Current` is loading #{parser.name}, " \
           "but you are running #{RUBY_VERSION.to_f}."
      ParserCurrent = parser
    end
  end
end
