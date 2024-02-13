# frozen_string_literal: true

module Prism
  # This module is responsible for converting the prism syntax tree into other
  # syntax trees.
  module Translation
    autoload :Parser, "prism/translation/parser"
    autoload :Ripper, "prism/translation/ripper"
    autoload :RubyParser, "prism/translation/ruby_parser"
  end
end
