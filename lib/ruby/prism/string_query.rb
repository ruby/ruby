# frozen_string_literal: true
# :markup: markdown
#--
# rbs_inline: enabled

module Ruby::Prism
  # Query methods that allow categorizing strings based on their context for
  # where they could be valid in a Ruby syntax tree.
  class StringQuery
    # Each query takes the version of Ruby to answer for, as the version option
    # of the parse methods reads it. It defaults to the nearest version to the
    # running Ruby.
    #
    # @rbs!
    #    def self.local?: (String string, ?version: String?) -> bool
    #    def self.constant?: (String string, ?version: String?) -> bool
    #    def self.method_name?: (String string, ?version: String?) -> bool
    #    def self.keyword?: (String string, ?version: String?) -> bool

    # The string that this query is wrapping.
    attr_reader :string #: String

    # Initialize a new query with the given string.
    #
    #: (String string) -> void
    def initialize(string)
      @string = string
    end

    # Whether or not this string is a valid local variable name.
    #
    #: (?version: String?) -> bool
    def local?(version: nil)
      StringQuery.local?(string, version: version)
    end

    # Whether or not this string is a valid constant name.
    #
    #: (?version: String?) -> bool
    def constant?(version: nil)
      StringQuery.constant?(string, version: version)
    end

    # Whether or not this string is a valid method name.
    #
    #: (?version: String?) -> bool
    def method_name?(version: nil)
      StringQuery.method_name?(string, version: version)
    end

    # Whether or not this string is a valid keyword.
    #
    #: (?version: String?) -> bool
    def keyword?(version: nil)
      StringQuery.keyword?(string, version: version)
    end
  end
end
