require_relative "formatter"

module ErrorHighlight
  module CoreExt
    # This is a marker to let `DidYouMean::Correctable#original_message` skip
    # the following method definition of `to_s`.
    # See https://github.com/ruby/did_you_mean/pull/152
    SKIP_TO_S_FOR_SUPER_LOOKUP = true
    private_constant :SKIP_TO_S_FOR_SUPER_LOOKUP

    def to_s
      msg = super.dup

      locs = backtrace_locations
      return msg unless locs

      loc = locs.first
      begin
        node = RubyVM::AbstractSyntaxTree.of(loc, save_script_lines: true)
        opts = {}

        case self
        when NoMethodError, NameError
          point = :name
          opts[:name] = name
        when TypeError, ArgumentError
          point = :args
        end

        spot = ErrorHighlight.spot(node, point, **opts) do |lineno, last_lineno|
          last_lineno ||= lineno
          node.script_lines[lineno - 1 .. last_lineno - 1].join("")
        end

      rescue Errno::ENOENT
      end

      if spot
        points = ErrorHighlight.formatter.message_for(spot)
        msg << points if !msg.include?(points)
      end

      msg
    end
  end

  NameError.prepend(CoreExt)

  # The extension for TypeError/ArgumentError is temporarily disabled due to many test failures

  #TypeError.prepend(CoreExt)
  #ArgumentError.prepend(CoreExt)
end
