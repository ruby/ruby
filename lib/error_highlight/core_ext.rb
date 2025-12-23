require_relative "formatter"

module ErrorHighlight
  module CoreExt
    private def generate_snippet
      if ArgumentError === self && message =~ /\A(?:wrong number of arguments|missing keyword[s]?|unknown keyword[s]?|no keywords accepted)\b/
        locs = self.backtrace_locations
        return "" if locs.size < 2
        callee_loc, caller_loc = locs
        callee_spot = ErrorHighlight.spot(self, backtrace_location: callee_loc, point_type: :name)
        caller_spot = ErrorHighlight.spot(self, backtrace_location: caller_loc, point_type: :name)
        if caller_spot && callee_spot &&
            caller_loc.path == callee_loc.path &&
            caller_loc.lineno == callee_loc.lineno &&
            caller_spot == callee_spot
          callee_loc = callee_spot = nil
        end
        ret = +"\n"
        [["caller", caller_loc, caller_spot], ["callee", callee_loc, callee_spot]].each do |header, loc, spot|
          out = nil
          if loc
            out = "    #{ header }: #{ loc.path }:#{ loc.lineno }"
            if spot
              _, _, snippet, highlight = ErrorHighlight.formatter.message_for(spot).lines
              out += "\n    | #{ snippet }      #{ highlight }"
            else
              # do nothing
            end
          end
          ret << "\n" + out if out
        end
        ret
      else
        spot = ErrorHighlight.spot(self)
        return "" unless spot
        return ErrorHighlight.formatter.message_for(spot)
      end
    end

    if Exception.method_defined?(:detailed_message)
      def detailed_message(highlight: false, error_highlight: true, **)
        return super unless error_highlight
        snippet = generate_snippet
        if highlight
          snippet = snippet.gsub(/.+/) { "\e[1m" + $& + "\e[m" }
        end
        super + snippet
      end
    else
      # This is a marker to let `DidYouMean::Correctable#original_message` skip
      # the following method definition of `to_s`.
      # See https://github.com/ruby/did_you_mean/pull/152
      SKIP_TO_S_FOR_SUPER_LOOKUP = true
      private_constant :SKIP_TO_S_FOR_SUPER_LOOKUP

      def to_s
        msg = super
        snippet = generate_snippet
        if snippet != "" && !msg.include?(snippet)
          msg + snippet
        else
          msg
        end
      end
    end
  end

  NameError.prepend(CoreExt)

  if Exception.method_defined?(:detailed_message)
    # ErrorHighlight is enabled for TypeError and ArgumentError only when Exception#detailed_message is available.
    # This is because changing ArgumentError#message is highly incompatible.
    TypeError.prepend(CoreExt)
    ArgumentError.prepend(CoreExt)
  end
end
