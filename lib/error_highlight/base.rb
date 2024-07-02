require_relative "version"

module ErrorHighlight
  # Identify the code fragment at that a given exception occurred.
  #
  # Options:
  #
  # point_type: :name | :args
  #   :name (default) points the method/variable name that the exception occurred.
  #   :args points the arguments of the method call that the exception occurred.
  #
  # backtrace_location: Thread::Backtrace::Location
  #   It locates the code fragment of the given backtrace_location.
  #   By default, it uses the first frame of backtrace_locations of the given exception.
  #
  # Returns:
  #  {
  #    first_lineno: Integer,
  #    first_column: Integer,
  #    last_lineno: Integer,
  #    last_column: Integer,
  #    snippet: String,
  #    script_lines: [String],
  #  } | nil
  #
  # Limitations:
  #
  # Currently, ErrorHighlight.spot only supports a single-line code fragment.
  # Therefore, if the return value is not nil, first_lineno and last_lineno will have
  # the same value. If the relevant code fragment spans multiple lines
  # (e.g., Array#[] of +ary[(newline)expr(newline)]+), the method will return nil.
  # This restriction may be removed in the future.
  def self.spot(obj, **opts)
    case obj
    when Exception
      exc = obj
      loc = opts[:backtrace_location]
      opts = { point_type: opts.fetch(:point_type, :name) }

      unless loc
        case exc
        when TypeError, ArgumentError
          opts[:point_type] = :args
        end

        locs = exc.backtrace_locations
        return nil unless locs

        loc = locs.first
        return nil unless loc

        opts[:name] = exc.name if NameError === obj
      end

      return nil unless Thread::Backtrace::Location === loc

      node =
        begin
          RubyVM::AbstractSyntaxTree.of(loc, keep_script_lines: true)
        rescue RuntimeError => error
          # RubyVM::AbstractSyntaxTree.of raises an error with a message that
          # includes "prism" when the ISEQ was compiled with the prism compiler.
          # In this case, we'll try to parse again with prism instead.
          raise unless error.message.include?("prism")
          require "prism"
          Prism.of(loc)
        end

      Spotter.new(node, **opts).spot

    when RubyVM::AbstractSyntaxTree::Node, Prism::Node
      Spotter.new(obj, **opts).spot

    else
      raise TypeError, "Exception is expected"
    end

  rescue SyntaxError,
         SystemCallError, # file not found or something
         ArgumentError # eval'ed code

    return nil
  end

  class Spotter
    class NonAscii < Exception; end
    private_constant :NonAscii

    def initialize(node, point_type: :name, name: nil)
      @node = node
      @point_type = point_type
      @name = name

      # Not-implemented-yet options
      @arg = nil # Specify the index or keyword at which argument caused the TypeError/ArgumentError
      @multiline = false # Allow multiline spot

      @fetch = -> (lineno, last_lineno = lineno) do
        snippet = @node.script_lines[lineno - 1 .. last_lineno - 1].join("")
        snippet += "\n" unless snippet.end_with?("\n")

        # It require some work to support Unicode (or multibyte) characters.
        # Tentatively, we stop highlighting if the code snippet has non-ascii characters.
        # See https://github.com/ruby/error_highlight/issues/4
        raise NonAscii unless snippet.ascii_only?

        snippet
      end
    end

    OPT_GETCONSTANT_PATH = (RUBY_VERSION.split(".").map {|s| s.to_i } <=> [3, 2]) >= 0
    private_constant :OPT_GETCONSTANT_PATH

    def spot
      return nil unless @node

      if OPT_GETCONSTANT_PATH
        # In Ruby 3.2 or later, a nested constant access (like `Foo::Bar::Baz`)
        # is compiled to one instruction (opt_getconstant_path).
        # @node points to the node of the whole `Foo::Bar::Baz` even if `Foo`
        # or `Foo::Bar` causes NameError.
        # So we try to spot the sub-node that causes the NameError by using
        # `NameError#name`.
        case @node.type
        when :COLON2
          subnodes = []
          node = @node
          while node.type == :COLON2
            node2, const = node.children
            subnodes << node if const == @name
            node = node2
          end
          if node.type == :CONST || node.type == :COLON3
            if node.children.first == @name
              subnodes << node
            end

            # If we found only one sub-node whose name is equal to @name, use it
            return nil if subnodes.size != 1
            @node = subnodes.first
          else
            # Do nothing; opt_getconstant_path is used only when the const base
            # is NODE_CONST (`Foo`) or NODE_COLON3 (`::Foo`)
          end
        when :constant_path_node
          subnodes = []
          node = @node

          begin
            subnodes << node if node.name == @name
          end while (node = node.parent).is_a?(Prism::ConstantPathNode)

          if node&.type == :constant_read_node && node.name == @name
            subnodes << node
          end

          # If we found only one sub-node whose name is equal to @name, use it
          return nil if subnodes.size != 1
          @node = subnodes.first
        end
      end

      case @node.type

      when :CALL, :QCALL
        case @point_type
        when :name
          spot_call_for_name
        when :args
          spot_call_for_args
        end

      when :ATTRASGN
        case @point_type
        when :name
          spot_attrasgn_for_name
        when :args
          spot_attrasgn_for_args
        end

      when :OPCALL
        case @point_type
        when :name
          spot_opcall_for_name
        when :args
          spot_opcall_for_args
        end

      when :FCALL
        case @point_type
        when :name
          spot_fcall_for_name
        when :args
          spot_fcall_for_args
        end

      when :VCALL
        spot_vcall

      when :OP_ASGN1
        case @point_type
        when :name
          spot_op_asgn1_for_name
        when :args
          spot_op_asgn1_for_args
        end

      when :OP_ASGN2
        case @point_type
        when :name
          spot_op_asgn2_for_name
        when :args
          spot_op_asgn2_for_args
        end

      when :CONST
        spot_vcall

      when :COLON2
        spot_colon2

      when :COLON3
        spot_vcall

      when :OP_CDECL
        spot_op_cdecl

      when :call_node
        case @point_type
        when :name
          prism_spot_call_for_name
        when :args
          prism_spot_call_for_args
        end

      when :local_variable_operator_write_node
        case @point_type
        when :name
          prism_spot_local_variable_operator_write_for_name
        when :args
          prism_spot_local_variable_operator_write_for_args
        end

      when :call_operator_write_node
        case @point_type
        when :name
          prism_spot_call_operator_write_for_name
        when :args
          prism_spot_call_operator_write_for_args
        end

      when :index_operator_write_node
        case @point_type
        when :name
          prism_spot_index_operator_write_for_name
        when :args
          prism_spot_index_operator_write_for_args
        end

      when :constant_read_node
        prism_spot_constant_read

      when :constant_path_node
        prism_spot_constant_path

      when :constant_path_operator_write_node
        prism_spot_constant_path_operator_write

      end

      if @snippet && @beg_column && @end_column && @beg_column < @end_column
        return {
          first_lineno: @beg_lineno,
          first_column: @beg_column,
          last_lineno: @end_lineno,
          last_column: @end_column,
          snippet: @snippet,
          script_lines: @node.script_lines,
        }
      else
        return nil
      end

    rescue NonAscii
      nil
    end

    private

    # Example:
    #   x.foo
    #    ^^^^
    #   x.foo(42)
    #    ^^^^
    #   x&.foo
    #    ^^^^^
    #   x[42]
    #    ^^^^
    #   x += 1
    #     ^
    def spot_call_for_name
      nd_recv, mid, nd_args = @node.children
      lineno = nd_recv.last_lineno
      lines = @fetch[lineno, @node.last_lineno]
      if mid == :[] && lines.match(/\G[\s)]*(\[(?:\s*\])?)/, nd_recv.last_column)
        @beg_column = $~.begin(1)
        @snippet = lines[/.*\n/]
        @beg_lineno = @end_lineno = lineno
        if nd_args
          if nd_recv.last_lineno == nd_args.last_lineno && @snippet.match(/\s*\]/, nd_args.last_column)
            @end_column = $~.end(0)
          end
        else
          if lines.match(/\G[\s)]*?\[\s*\]/, nd_recv.last_column)
            @end_column = $~.end(0)
          end
        end
      elsif lines.match(/\G[\s)]*?(\&?\.)(\s*?)(#{ Regexp.quote(mid) }).*\n/, nd_recv.last_column)
        lines = $` + $&
        @beg_column = $~.begin($2.include?("\n") ? 3 : 1)
        @end_column = $~.end(3)
        if i = lines[..@beg_column].rindex("\n")
          @beg_lineno = @end_lineno = lineno + lines[..@beg_column].count("\n")
          @snippet = lines[i + 1..]
          @beg_column -= i + 1
          @end_column -= i + 1
        else
          @snippet = lines
          @beg_lineno = @end_lineno = lineno
        end
      elsif mid.to_s =~ /\A\W+\z/ && lines.match(/\G\s*(#{ Regexp.quote(mid) })=.*\n/, nd_recv.last_column)
        @snippet = $` + $&
        @beg_column = $~.begin(1)
        @end_column = $~.end(1)
      end
    end

    # Example:
    #   x.foo(42)
    #         ^^
    #   x[42]
    #     ^^
    #   x += 1
    #        ^
    def spot_call_for_args
      _nd_recv, _mid, nd_args = @node.children
      if nd_args && nd_args.first_lineno == nd_args.last_lineno
        fetch_line(nd_args.first_lineno)
        @beg_column = nd_args.first_column
        @end_column = nd_args.last_column
      end
      # TODO: support @arg
    end

    # Example:
    #   x.foo = 1
    #    ^^^^^^
    #   x[42] = 1
    #    ^^^^^^
    def spot_attrasgn_for_name
      nd_recv, mid, nd_args = @node.children
      *nd_args, _nd_last_arg, _nil = nd_args.children
      fetch_line(nd_recv.last_lineno)
      if mid == :[]= && @snippet.match(/\G[\s)]*(\[)/, nd_recv.last_column)
        @beg_column = $~.begin(1)
        args_last_column = $~.end(0)
        if nd_args.last && nd_recv.last_lineno == nd_args.last.last_lineno
          args_last_column = nd_args.last.last_column
        end
        if @snippet.match(/[\s)]*\]\s*=/, args_last_column)
          @end_column = $~.end(0)
        end
      elsif @snippet.match(/\G[\s)]*(\.\s*#{ Regexp.quote(mid.to_s.sub(/=\z/, "")) }\s*=)/, nd_recv.last_column)
        @beg_column = $~.begin(1)
        @end_column = $~.end(1)
      end
    end

    # Example:
    #   x.foo = 1
    #           ^
    #   x[42] = 1
    #     ^^^^^^^
    #   x[] = 1
    #     ^^^^^
    def spot_attrasgn_for_args
      nd_recv, mid, nd_args = @node.children
      fetch_line(nd_recv.last_lineno)
      if mid == :[]= && @snippet.match(/\G[\s)]*\[/, nd_recv.last_column)
        @beg_column = $~.end(0)
        if nd_recv.last_lineno == nd_args.last_lineno
          @end_column = nd_args.last_column
        end
      elsif nd_args && nd_args.first_lineno == nd_args.last_lineno
        @beg_column = nd_args.first_column
        @end_column = nd_args.last_column
      end
      # TODO: support @arg
    end

    # Example:
    #   x + 1
    #     ^
    #   +x
    #   ^
    def spot_opcall_for_name
      nd_recv, op, nd_arg = @node.children
      fetch_line(nd_recv.last_lineno)
      if nd_arg
        # binary operator
        if @snippet.match(/\G[\s)]*(#{ Regexp.quote(op) })/, nd_recv.last_column)
          @beg_column = $~.begin(1)
          @end_column = $~.end(1)
        end
      else
        # unary operator
        if @snippet[...nd_recv.first_column].match(/(#{ Regexp.quote(op.to_s.sub(/@\z/, "")) })\s*\(?\s*\z/)
          @beg_column = $~.begin(1)
          @end_column = $~.end(1)
        end
      end
    end

    # Example:
    #   x + 1
    #       ^
    def spot_opcall_for_args
      _nd_recv, _op, nd_arg = @node.children
      if nd_arg && nd_arg.first_lineno == nd_arg.last_lineno
        # binary operator
        fetch_line(nd_arg.first_lineno)
        @beg_column = nd_arg.first_column
        @end_column = nd_arg.last_column
      end
    end

    # Example:
    #   foo(42)
    #   ^^^
    #   foo 42
    #   ^^^
    def spot_fcall_for_name
      mid, _nd_args = @node.children
      fetch_line(@node.first_lineno)
      if @snippet.match(/(#{ Regexp.quote(mid) })/, @node.first_column)
        @beg_column = $~.begin(1)
        @end_column = $~.end(1)
      end
    end

    # Example:
    #   foo(42)
    #       ^^
    #   foo 42
    #       ^^
    def spot_fcall_for_args
      _mid, nd_args = @node.children
      if nd_args && nd_args.first_lineno == nd_args.last_lineno
        # binary operator
        fetch_line(nd_args.first_lineno)
        @beg_column = nd_args.first_column
        @end_column = nd_args.last_column
      end
    end

    # Example:
    #   foo
    #   ^^^
    def spot_vcall
      if @node.first_lineno == @node.last_lineno
        fetch_line(@node.last_lineno)
        @beg_column = @node.first_column
        @end_column = @node.last_column
      end
    end

    # Example:
    #   x[1] += 42
    #    ^^^    (for [])
    #   x[1] += 42
    #        ^  (for +)
    #   x[1] += 42
    #    ^^^^^^ (for []=)
    def spot_op_asgn1_for_name
      nd_recv, op, nd_args, _nd_rhs = @node.children
      fetch_line(nd_recv.last_lineno)
      if @snippet.match(/\G[\s)]*(\[)/, nd_recv.last_column)
        bracket_beg_column = $~.begin(1)
        args_last_column = $~.end(0)
        if nd_args && nd_recv.last_lineno == nd_args.last_lineno
          args_last_column = nd_args.last_column
        end
        if @snippet.match(/\s*\](\s*)(#{ Regexp.quote(op) })=()/, args_last_column)
          case @name
          when :[], :[]=
            @beg_column = bracket_beg_column
            @end_column = $~.begin(@name == :[] ? 1 : 3)
          when op
            @beg_column = $~.begin(2)
            @end_column = $~.end(2)
          end
        end
      end
    end

    # Example:
    #   x[1] += 42
    #     ^^^^^^^^
    def spot_op_asgn1_for_args
      nd_recv, mid, nd_args, nd_rhs = @node.children
      fetch_line(nd_recv.last_lineno)
      if mid == :[]= && @snippet.match(/\G\s*\[/, nd_recv.last_column)
        @beg_column = $~.end(0)
        if nd_recv.last_lineno == nd_rhs.last_lineno
          @end_column = nd_rhs.last_column
        end
      elsif nd_args && nd_args.first_lineno == nd_rhs.last_lineno
        @beg_column = nd_args.first_column
        @end_column = nd_rhs.last_column
      end
      # TODO: support @arg
    end

    # Example:
    #   x.foo += 42
    #    ^^^     (for foo)
    #   x.foo += 42
    #         ^  (for +)
    #   x.foo += 42
    #    ^^^^^^^ (for foo=)
    def spot_op_asgn2_for_name
      nd_recv, _qcall, attr, op, _nd_rhs = @node.children
      fetch_line(nd_recv.last_lineno)
      if @snippet.match(/\G[\s)]*(\.)\s*#{ Regexp.quote(attr) }()\s*(#{ Regexp.quote(op) })(=)/, nd_recv.last_column)
        case @name
        when attr
          @beg_column = $~.begin(1)
          @end_column = $~.begin(2)
        when op
          @beg_column = $~.begin(3)
          @end_column = $~.end(3)
        when :"#{ attr }="
          @beg_column = $~.begin(1)
          @end_column = $~.end(4)
        end
      end
    end

    # Example:
    #   x.foo += 42
    #            ^^
    def spot_op_asgn2_for_args
      _nd_recv, _qcall, _attr, _op, nd_rhs = @node.children
      if nd_rhs.first_lineno == nd_rhs.last_lineno
        fetch_line(nd_rhs.first_lineno)
        @beg_column = nd_rhs.first_column
        @end_column = nd_rhs.last_column
      end
    end

    # Example:
    #   Foo::Bar
    #      ^^^^^
    def spot_colon2
      nd_parent, const = @node.children
      if nd_parent.last_lineno == @node.last_lineno
        fetch_line(nd_parent.last_lineno)
        @beg_column = nd_parent.last_column
        @end_column = @node.last_column
      else
        @snippet = @fetch[@node.last_lineno]
        if @snippet[...@node.last_column].match(/#{ Regexp.quote(const) }\z/)
          @beg_column = $~.begin(0)
          @end_column = $~.end(0)
        end
      end
    end

    # Example:
    #   Foo::Bar += 1
    #      ^^^^^^^^
    def spot_op_cdecl
      nd_lhs, op, _nd_rhs = @node.children
      *nd_parent_lhs, _const = nd_lhs.children
      if @name == op
        @snippet = @fetch[nd_lhs.last_lineno]
        if @snippet.match(/\G\s*(#{ Regexp.quote(op) })=/, nd_lhs.last_column)
          @beg_column = $~.begin(1)
          @end_column = $~.end(1)
        end
      else
        # constant access error
        @end_column = nd_lhs.last_column
        if nd_parent_lhs.empty? # example: ::C += 1
          if nd_lhs.first_lineno == nd_lhs.last_lineno
            @snippet = @fetch[nd_lhs.last_lineno]
            @beg_column = nd_lhs.first_column
          end
        else # example: Foo::Bar::C += 1
          if nd_parent_lhs.last.last_lineno == nd_lhs.last_lineno
            @snippet = @fetch[nd_lhs.last_lineno]
            @beg_column = nd_parent_lhs.last.last_column
          end
        end
      end
    end

    def fetch_line(lineno)
      @beg_lineno = @end_lineno = lineno
      @snippet = @fetch[lineno]
    end

    # Take a location from the prism parser and set the necessary instance
    # variables.
    def prism_location(location)
      @beg_lineno = location.start_line
      @beg_column = location.start_column
      @end_lineno = location.end_line
      @end_column = location.end_column
      @snippet = @fetch[@beg_lineno, @end_lineno]
    end

    # Example:
    #   x.foo
    #    ^^^^
    #   x.foo(42)
    #    ^^^^
    #   x&.foo
    #    ^^^^^
    #   x[42]
    #    ^^^^
    #   x.foo = 1
    #    ^^^^^^
    #   x[42] = 1
    #    ^^^^^^
    #   x + 1
    #     ^
    #   +x
    #   ^
    #   foo(42)
    #   ^^^
    #   foo 42
    #   ^^^
    #   foo
    #   ^^^
    def prism_spot_call_for_name
      # Explicitly turn off foo.() syntax because error_highlight expects this
      # to not work.
      return nil if @node.name == :call && @node.message_loc.nil?

      location = @node.message_loc || @node.call_operator_loc || @node.location
      location = @node.call_operator_loc.join(location) if @node.call_operator_loc&.start_line == location.start_line

      # If the method name ends with "=" but the message does not, then this is
      # a method call using the "attribute assignment" syntax
      # (e.g., foo.bar = 1). In this case we need to go retrieve the = sign and
      # add it to the location.
      if (name = @node.name).end_with?("=") && !@node.message.end_with?("=")
        location = location.adjoin("=")
      end

      prism_location(location)

      if !name.end_with?("=") && !name.match?(/[[:alpha:]_\[]/)
        # If the method name is an operator, then error_highlight only
        # highlights the first line.
        fetch_line(location.start_line)
      end
    end

    # Example:
    #   x.foo(42)
    #         ^^
    #   x[42]
    #     ^^
    #   x.foo = 1
    #           ^
    #   x[42] = 1
    #     ^^^^^^^
    #   x[] = 1
    #     ^^^^^
    #   x + 1
    #       ^
    #   foo(42)
    #       ^^
    #   foo 42
    #       ^^
    def prism_spot_call_for_args
      # Explicitly turn off foo.() syntax because error_highlight expects this
      # to not work.
      return nil if @node.name == :call && @node.message_loc.nil?

      if @node.name == :[]= && @node.opening == "[" && (@node.arguments&.arguments || []).length == 1
        prism_location(@node.opening_loc.copy(start_offset: @node.opening_loc.start_offset + 1).join(@node.arguments.location))
      else
        prism_location(@node.arguments.location)
      end
    end

    # Example:
    #   x += 1
    #     ^
    def prism_spot_local_variable_operator_write_for_name
      prism_location(@node.binary_operator_loc.chop)
    end

    # Example:
    #   x += 1
    #        ^
    def prism_spot_local_variable_operator_write_for_args
      prism_location(@node.value.location)
    end

    # Example:
    #   x.foo += 42
    #    ^^^     (for foo)
    #   x.foo += 42
    #         ^  (for +)
    #   x.foo += 42
    #    ^^^^^^^ (for foo=)
    def prism_spot_call_operator_write_for_name
      if !@name.start_with?(/[[:alpha:]_]/)
        prism_location(@node.binary_operator_loc.chop)
      else
        location = @node.message_loc
        if @node.call_operator_loc.start_line == location.start_line
          location = @node.call_operator_loc.join(location)
        end

        location = location.adjoin("=") if @name.end_with?("=")
        prism_location(location)
      end
    end

    # Example:
    #   x.foo += 42
    #            ^^
    def prism_spot_call_operator_write_for_args
      prism_location(@node.value.location)
    end

    # Example:
    #   x[1] += 42
    #    ^^^    (for [])
    #   x[1] += 42
    #        ^  (for +)
    #   x[1] += 42
    #    ^^^^^^ (for []=)
    def prism_spot_index_operator_write_for_name
      case @name
      when :[]
        prism_location(@node.opening_loc.join(@node.closing_loc))
      when :[]=
        prism_location(@node.opening_loc.join(@node.closing_loc).adjoin("="))
      else
        # Explicitly turn off foo[] += 1 syntax when the operator is not on
        # the same line because error_highlight expects this to not work.
        return nil if @node.binary_operator_loc.start_line != @node.opening_loc.start_line

        prism_location(@node.binary_operator_loc.chop)
      end
    end

    # Example:
    #   x[1] += 42
    #     ^^^^^^^^
    def prism_spot_index_operator_write_for_args
      opening_loc =
        if @node.arguments.nil?
          @node.opening_loc.copy(start_offset: @node.opening_loc.start_offset + 1)
        else
          @node.arguments.location
        end

      prism_location(opening_loc.join(@node.value.location))
    end

    # Example:
    #   Foo
    #   ^^^
    def prism_spot_constant_read
      prism_location(@node.location)
    end

    # Example:
    #   Foo::Bar
    #      ^^^^^
    def prism_spot_constant_path
      if @node.parent && @node.parent.location.end_line == @node.location.end_line
        fetch_line(@node.parent.location.end_line)
        prism_location(@node.delimiter_loc.join(@node.name_loc))
      else
        fetch_line(@node.location.end_line)
        location = @node.name_loc
        location = @node.delimiter_loc.join(location) if @node.delimiter_loc.end_line == location.start_line
        prism_location(location)
      end
    end

    # Example:
    #   Foo::Bar += 1
    #      ^^^^^^^^
    def prism_spot_constant_path_operator_write
      if @name == (target = @node.target).name
        prism_location(target.delimiter_loc.join(target.name_loc))
      else
        prism_location(@node.binary_operator_loc.chop)
      end
    end
  end

  private_constant :Spotter
end
