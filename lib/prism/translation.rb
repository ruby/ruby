# frozen_string_literal: true
# :markup: markdown

module Prism
  # This module is responsible for converting the prism syntax tree into other
  # syntax trees.
  module Translation # steep:ignore
    autoload :Parser, "prism/translation/parser"
    autoload :ParserCurrent, "prism/translation/parser_current"
    autoload :Parser33, "prism/translation/parser33"
    autoload :Parser34, "prism/translation/parser34"
    autoload :Parser35, "prism/translation/parser35"
    autoload :Parser40, "prism/translation/parser40"
    autoload :Parser41, "prism/translation/parser41"
    autoload :Ripper, "prism/translation/ripper"
    autoload :RubyParser, "prism/translation/ruby_parser"
  end
end
