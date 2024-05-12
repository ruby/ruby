# frozen_string_literal: true

# Simple DSL implementation for Ripper code generation
#
# input: /*% ripper: stmts_add!(stmts_new!, void_stmt!) %*/
# output:
#   VALUE v1, v2;
#   v1 = dispatch0(stmts_new);
#   v2 = dispatch0(void_stmt);
#   $$ = dispatch2(stmts_add, v1, v2);
#
# - The code must be a single line.
#
# - The code is basically Ruby code, even if it appears like in C and
#   the result will be processed as C. e.g., comments need to be in
#   Ruby style.

class DSL
  TAG_PATTERN = /(?><[a-zA-Z0-9_]+>)/.source
  NAME_PATTERN = /(?>\$|\d+|[a-zA-Z_][a-zA-Z0-9_]*|\[[a-zA-Z_.][-a-zA-Z0-9_.]*\])(?>(?:\.|->)[a-zA-Z_][a-zA-Z0-9_]*)*/.source
  NOT_REF_PATTERN = /(?>\#.*|[^\"$@]*|"(?>\\.|[^\"])*")/.source

  def self.line?(line, lineno = nil, indent: nil)
    if %r<(?<space>\s*)/\*% *ripper(?:\[(?<option>.*?)\])?: *(?<code>.*?) *%\*/> =~ line
      new(code, comma_split(option), lineno, indent: indent || space)
    end
  end

  def self.comma_split(str)
    str or return []
    str.scan(/(([^(,)]+|\((?:,|\g<0>)*\))+)/).map(&:first)
  end

  using Module.new {
    refine Array do
      def to_s
        if empty?
          "rb_ary_new()"
        else
          "rb_ary_new_from_args(#{size}, #{map(&:to_s).join(', ')})"
        end
      end
    end
  }

  def initialize(code, options, lineno = nil, indent: "\t\t\t")
    @lineno = lineno
    @indent = indent
    @events = {}
    @error = options.include?("error")
    @brace = options.include?("brace")
    if options.include?("final")
      @final = "p->result"
    else
      @final = (options.grep(/\A\$#{NAME_PATTERN}\z/o)[0] || "p->s_lvalue")
    end
    @vars = 0

    # struct parser_params *p
    p = p = "p"

    @code = +""
    code = code.gsub(%r[\G#{NOT_REF_PATTERN}\K(\$|\$:|@)#{TAG_PATTERN}?#{NAME_PATTERN}]o) {
      if (arg = $&) == "$:$"
        '"p->s_lvalue"'
      elsif arg.start_with?("$:")
        %["get_value(#{arg})"]
      else
        arg.dump
      end
    }
    @last_value = eval(code)
  rescue SyntaxError
    $stderr.puts "error on line #{@lineno}" if @lineno
    raise
  end

  attr_reader :events

  undef lambda
  undef hash
  undef class

  def generate
    s = "#@code#@final=#@last_value;"
    s = "{VALUE #{ (1..@vars).map {|v| "v#{ v }" }.join(",") };#{ s }}" if @vars > 0
    s << "ripper_error(p);" if @error
    s = "{#{ s }}" if @brace
    "#{@indent}#{s}"
  end

  def new_var
    "v#{ @vars += 1 }"
  end

  def add_event(event, args)
    event = event.to_s.sub(/!\z/, "")
    @events[event] = args.size
    vars = []
    args.each do |arg|
      vars << v = new_var
      @code << "#{ v }=#{ arg };"
    end
    v = new_var
    d = "dispatch#{ args.size }(#{ [event, *vars].join(",") })"
    @code << "#{ v }=#{ d };"
    v
  end

  def method_missing(event, *args)
    if event.to_s =~ /!\z/
      add_event(event, args)
    elsif args.empty? and /\Aid[A-Z_]/ =~ event.to_s
      event
    else
      "#{ event }(#{ args.map(&:to_s).join(", ") })"
    end
  end

  def self.const_missing(name)
    name
  end
end
