# frozen_string_literal: true
# :markup: markdown

module Prism
  module Translation
    # This class is the entry-point for Ruby 4.0 of `Prism::Translation::Parser`.
    class Parser40 < Parser
      def version # :nodoc:
        40
      end
    end
  end
end
