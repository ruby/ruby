# frozen_string_literal: true
# :markup: markdown
#--
# rbs_inline: enabled

module Prism
  class InNode < Node
    #: () -> String
    def in # :nodoc
      in_keyword
    end

    #: () -> Location
    def in_loc # :nodoc
      in_keyword_loc
    end

    #: () -> String?
    def then # :nodoc
      then_keyword
    end

    #: () -> Location?
    def then_loc # :nodoc
      then_keyword_loc
    end
  end

  class MatchPredicateNode < Node
    #: () -> String
    def operator # :nodoc
      keyword
    end

    #: () -> Location
    def operator_loc # :nodoc
      keyword_loc
    end
  end

  class UnlessNode < Node
    #: () -> String
    def keyword # :nodoc
      unless_keyword
    end

    #: () -> Location
    def keyword_loc # :nodoc
      unless_keyword_loc
    end
  end

  class UntilNode < Node
    #: () -> String
    def keyword # :nodoc
      until_keyword
    end

    #: () -> Location
    def keyword_loc # :nodoc
      until_keyword_loc
    end

    #: () -> String?
    def closing # :nodoc
      end_keyword
    end

    #: () -> Location?
    def closing_loc # :nodoc
      end_keyword_loc
    end
  end

  class WhenNode < Node
    #: () -> String
    def keyword # :nodoc
      when_keyword
    end

    #: () -> Location
    def keyword_loc # :nodoc
      when_keyword_loc
    end
  end

  class WhileNode < Node
    #: () -> String
    def keyword # :nodoc
      while_keyword
    end

    #: () -> Location
    def keyword_loc # :nodoc
      while_keyword_loc
    end

    #: () -> String?
    def closing # :nodoc
      end_keyword
    end

    #: () -> Location?
    def closing_loc # :nodoc
      end_keyword_loc
    end
  end
end
