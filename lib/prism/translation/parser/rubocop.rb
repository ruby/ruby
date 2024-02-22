# frozen_string_literal: true

require "parser"
require "rubocop"

require "prism"
require "prism/translation/parser"

module Prism
  module Translation
    class Parser
      # This is the special version numbers that should be used in RuboCop
      # configuration files to trigger using prism.

      # For Ruby 3.3
      VERSION_3_3 = 80_82_73_83_77.33

      # For Ruby 3.4
      VERSION_3_4 = 80_82_73_83_77.34

      # This module gets prepended into RuboCop::AST::ProcessedSource.
      module ProcessedSource
        # Redefine parser_class so that we can inject the prism parser into the
        # list of known parsers.
        def parser_class(ruby_version)
          if ruby_version == Prism::Translation::Parser::VERSION_3_3
            require "prism/translation/parser33"
            Prism::Translation::Parser33
          elsif ruby_version == Prism::Translation::Parser::VERSION_3_4
            require "prism/translation/parser34"
            Prism::Translation::Parser34
          else
            super
          end
        end
      end
    end
  end
end

# :stopdoc:
RuboCop::AST::ProcessedSource.prepend(Prism::Translation::Parser::ProcessedSource)
known_rubies = RuboCop::TargetRuby.const_get(:KNOWN_RUBIES)
RuboCop::TargetRuby.send(:remove_const, :KNOWN_RUBIES)
RuboCop::TargetRuby::KNOWN_RUBIES = [*known_rubies, Prism::Translation::Parser::VERSION_3_3].freeze
