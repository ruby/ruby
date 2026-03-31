# frozen_string_literal: true
# :markup: markdown

module Prism
  module Translation
    # This class is the entry-point for Ruby 3.3 of `Prism::Translation::Parser`.
    class Parser33 < Parser
      def version # :nodoc:
        33
      end
    end

    # This class is the entry-point for Ruby 3.4 of `Prism::Translation::Parser`.
    class Parser34 < Parser
      def version # :nodoc:
        34
      end
    end

    # This class is the entry-point for Ruby 4.0 of `Prism::Translation::Parser`.
    class Parser40 < Parser
      def version # :nodoc:
        40
      end
    end

    Parser35 = Parser40 # :nodoc:

    # This class is the entry-point for Ruby 4.1 of `Prism::Translation::Parser`.
    class Parser41 < Parser
      def version # :nodoc:
        41
      end
    end
  end
end
