module Lrama
  class Grammar
    # type: :dollar or :at
    # name: String (e.g. $$, $foo, $expr.right)
    # index: Integer (e.g. $1)
    # ex_tag: "$<tag>1" (Optional)
    class Reference < Struct.new(:type, :name, :index, :ex_tag, :first_column, :last_column, keyword_init: true)
      def value
        name || index
      end
    end
  end
end
