module ErrorHighlight
  module CoreExt
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
        marker = " " * spot[:first_column] + "^" * (spot[:last_column] - spot[:first_column])
        points = "\n\n#{ spot[:line] }#{ marker }"
        msg << points if !msg.include?(points)
      end

      msg
    end
  end

  NameError.prepend(CoreExt)

  # temporarily disabled
  #TypeError.prepend(CoreExt)
  #ArgumentError.prepend(CoreExt)
end
