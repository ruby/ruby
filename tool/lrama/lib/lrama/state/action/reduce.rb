# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class State
    class Action
      class Reduce
        # TODO: rbs-inline 0.11.0 doesn't support instance variables.
        #       Move these type declarations above instance variable definitions, once it's supported.
        #       see: https://github.com/soutaro/rbs-inline/pull/149
        #
        # @rbs!
        #   @item: Item
        #   @look_ahead: Array[Grammar::Symbol]?
        #   @look_ahead_sources: Hash[Grammar::Symbol, Array[Action::Goto]]?
        #   @not_selected_symbols: Array[Grammar::Symbol]

        attr_reader :item #: Item
        attr_reader :look_ahead #: Array[Grammar::Symbol]?
        attr_reader :look_ahead_sources #: Hash[Grammar::Symbol, Array[Action::Goto]]?
        attr_reader :not_selected_symbols #: Array[Grammar::Symbol]

        # https://www.gnu.org/software/bison/manual/html_node/Default-Reductions.html
        attr_accessor :default_reduction #: bool

        # @rbs (Item item) -> void
        def initialize(item)
          @item = item
          @look_ahead = nil
          @look_ahead_sources = nil
          @not_selected_symbols = []
        end

        # @rbs () -> Grammar::Rule
        def rule
          @item.rule
        end

        # @rbs (Array[Grammar::Symbol] look_ahead) -> Array[Grammar::Symbol]
        def look_ahead=(look_ahead)
          @look_ahead = look_ahead.freeze
        end

        # @rbs (Hash[Grammar::Symbol, Array[Action::Goto]] sources) -> Hash[Grammar::Symbol, Array[Action::Goto]]
        def look_ahead_sources=(sources)
          @look_ahead_sources = sources.freeze
        end

        # @rbs (Grammar::Symbol sym) -> Array[Grammar::Symbol]
        def add_not_selected_symbol(sym)
          @not_selected_symbols << sym
        end

        # @rbs () -> (::Array[Grammar::Symbol?])
        def selected_look_ahead
          if look_ahead
            look_ahead - @not_selected_symbols
          else
            []
          end
        end

        # @rbs () -> void
        def clear_conflicts
          @not_selected_symbols = []
          @default_reduction = nil
        end
      end
    end
  end
end
