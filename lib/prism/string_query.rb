# frozen_string_literal: true
# :markup: markdown
#--
# rbs_inline: enabled

module Prism
  # Query methods that allow categorizing strings based on their context for
  # where they could be valid in a Ruby syntax tree.
  class StringQuery
    # @rbs!
    #    def self.local?: (String string) -> bool
    #    def self.constant?: (String string) -> bool
    #    def self.method_name?: (String string) -> bool

    # The string that this query is wrapping.
    attr_reader :string #: String

    # Initialize a new query with the given string.
    #--
    #: (String string) -> void
    def initialize(string)
      @string = string
    end

    # Whether or not this string is a valid local variable name.
    #--
    #: () -> bool
    def local?
      StringQuery.local?(string)
    end

    # Whether or not this string is a valid constant name.
    #--
    #: () -> bool
    def constant?
      StringQuery.constant?(string)
    end

    # Whether or not this string is a valid method name.
    #--
    #: () -> bool
    def method_name?
      StringQuery.method_name?(string)
    end
  end
end
