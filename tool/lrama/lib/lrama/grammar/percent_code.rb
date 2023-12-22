module Lrama
  class Grammar
    class PercentCode
      attr_reader :id, :code

      def initialize(id, code)
        @id = id
        @code = code
      end
    end
  end
end
