module DidYouMean
  module Correctable
    def original_message
      method(:to_s).super_method.call
    end

    def to_s
      msg = super.dup
      suggestion = DidYouMean.formatter.message_for(corrections)

      msg << suggestion if !msg.end_with?(suggestion)
      msg
    rescue
      super
    end

    def corrections
      @corrections ||= spell_checker.corrections
    end

    def spell_checker
      SPELL_CHECKERS[self.class.to_s].new(self)
    end
  end
end
