# frozen_string_literal: true

module Prism
  # This module is responsible for converting the prism syntax tree into other
  # syntax trees. At the moment it only supports converting to the
  # whitequark/parser gem's syntax tree, but support is planned for the
  # seattlerb/ruby_parser gem's syntax tree as well.
  module Translation
    autoload :Parser, "prism/translation/parser"
  end
end
