# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Grammar
    # Grammar file information not used by States but by Output
    class Auxiliary
      attr_accessor :prologue_first_lineno #: Integer?
      attr_accessor :prologue #: String?
      attr_accessor :epilogue_first_lineno #: Integer?
      attr_accessor :epilogue #: String?
    end
  end
end
