module Lrama
  class Grammar
    # type: :dollar or :at
    # name: String (e.g. $$, $foo, $expr.right)
    # number: Integer (e.g. $1)
    # index: Integer
    # ex_tag: "$<tag>1" (Optional)
    class Reference < Struct.new(:type, :name, :number, :index, :ex_tag, :first_column, :last_column, keyword_init: true)
      def value
        name || number
      end
    end
  end
end
