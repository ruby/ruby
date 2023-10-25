module Lrama
  class Lexer
    class Token < Struct.new(:type, :s_value, :alias, keyword_init: true)
      class Type < Struct.new(:id, :name, keyword_init: true)
      end
    end
  end
end
