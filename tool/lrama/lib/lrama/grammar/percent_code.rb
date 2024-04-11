module Lrama
  class Grammar
    class PercentCode
      attr_reader :name, :code

      def initialize(name, code)
        @name = name
        @code = code
      end
    end
  end
end
