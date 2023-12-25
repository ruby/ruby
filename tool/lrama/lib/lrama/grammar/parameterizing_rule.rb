module Lrama
  class Grammar
    class ParameterizingRule < Struct.new(:rules, :token, keyword_init: true)
    end
  end
end
