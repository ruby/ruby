module Lrama
  class Grammar
    # Grammar file information not used by States but by Output
    class Auxiliary < Struct.new(:prologue_first_lineno, :prologue, :epilogue_first_lineno, :epilogue, keyword_init: true)
    end
  end
end
