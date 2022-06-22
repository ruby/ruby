require_relative "formatter"

module ErrorHighlight
  module CoreExt
    private def generate_snippet
      locs = backtrace_locations
      return "" unless locs

      loc = locs.first
      return "" unless loc

      begin
        node = RubyVM::AbstractSyntaxTree.of(loc, keep_script_lines: true)
        opts = {}

        case self
        when NoMethodError, NameError
          opts[:point_type] = :name
          opts[:name] = name
        when TypeError, ArgumentError
          opts[:point_type] = :args
        end

        spot = ErrorHighlight.spot(node, **opts)

      rescue SyntaxError
      rescue SystemCallError # file not found or something
      rescue ArgumentError   # eval'ed code
      end

      if spot
        return ErrorHighlight.formatter.message_for(spot)
      end

      ""
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

  # The extension for TypeError/ArgumentError is temporarily disabled due to many test failures

  #TypeError.prepend(CoreExt)
  #ArgumentError.prepend(CoreExt)
end
