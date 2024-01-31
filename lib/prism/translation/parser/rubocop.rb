# frozen_string_literal: true

require "parser"
require "rubocop"

require "prism"
require "prism/translation/parser"

module Prism
  module Translation
    class Parser
      # This is the special version number that should be used in rubocop
      # configuration files to trigger using prism.
      VERSION_3_3 = 80_82_73_83_77.33

      # This module gets prepended into RuboCop::AST::ProcessedSource.
      module ProcessedSource
        # Redefine parser_class so that we can inject the prism parser into the
        # list of known parsers.
        def parser_class(ruby_version)
          if ruby_version == Prism::Translation::Parser::VERSION_3_3
            require "prism/translation/parser"
            Prism::Translation::Parser
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
