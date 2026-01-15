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

  class Var
    class Table < Hash
      def initialize(&block)
        super() {|tbl, arg|
          tbl.fetch(arg, &block)
        }
      end

      def fetch(arg, &block)
        super {
          self[arg] = Var.new(self, arg, &block)
        }
      end

      def add(&block)
        v = new_var
        self[v] = Var.new(self, v, &block)
      end

      def defined?(name)
        name = name.to_s
        any? {|_, v| v.var == name}
      end

      def new_var
        "v#{size+1}"
      end
    end

    attr_reader :var, :value

    PRETTY_PRINT_INSTANCE_VARIABLES = instance_methods(false).freeze

    def pretty_print_instance_variables
      PRETTY_PRINT_INSTANCE_VARIABLES
    end

    alias to_s var

    def initialize(table, arg, &block)
      @var = table.new_var
      @value = yield arg
      @table = table
    end

    # Indexing.
    #
    #   $:1 -> v1=get_value($:1)
    #   $:1[0] -> rb_ary_entry(v1, 0)
    #   $:1[0..1] -> [rb_ary_entry(v1, 0), rb_ary_entry(v1, 1)]
    #   *$:1[0..1] -> rb_ary_entry(v1, 0), rb_ary_entry(v1, 1)
    #
    # Splat needs `[range]` because `Var` does not have the length info.
    def [](idx)
      if ::Range === idx
        idx.map {|i| self[i]}
      else
        @table.fetch("#@var[#{idx}]") {"rb_ary_entry(#{@var}, #{idx})"}
      end
    end
  end

  def initialize(code, options, lineno = nil, indent: "\t\t\t")
    @lineno = lineno
    @indent = indent
    @events = {}
    @error = options.include?("error")
    if options.include?("final")
      @final = "p->result"
    else
      @final = (options.grep(/\A\$#{NAME_PATTERN}\z/o)[0] || "p->s_lvalue")
    end

    bind = dsl_binding
    @var_table = Var::Table.new {|arg| "get_value(#{arg})"}
    code = code.gsub(%r[\G#{NOT_REF_PATTERN}\K(\$|\$:|@)#{TAG_PATTERN}?#{NAME_PATTERN}]o) {
      if (arg = $&) == "$:$"
        '"p->s_lvalue"'
      elsif arg.start_with?("$:")
        "(#{@var_table[arg]}=@var_table[#{arg.dump}])"
      else
        arg.dump
      end
    }
    @last_value = bind.eval(code)
  rescue SyntaxError
    $stderr.puts "error on line #{@lineno}" if @lineno
    raise
  end

  def dsl_binding(p = "p")
    # struct parser_params *p
    binding
  end

  attr_reader :events

  undef lambda
  undef hash
  undef :class

  def generate
    s = "#@final=#@last_value;"
    s << "ripper_error(p);" if @error
    unless @var_table.empty?
      vars = @var_table.map {|_, v| "#{v.var}=#{v.value}"}.join(", ")
      s = "VALUE #{ vars }; #{ s }"
    end
    "#{@indent}{#{s}}"
  end

  def add_event(event, args)
    event = event.to_s.sub(/!\z/, "")
    @events[event] = args.size
    vars = []
    args.each do |arg|
      arg = @var_table.add {arg} unless Var === arg
      vars << arg
    end
    @var_table.add {"dispatch#{ args.size }(#{ [event, *vars].join(",") })"}
  end

  def method_missing(event, *args)
    if event.to_s =~ /!\z/
      add_event(event, args)
    elsif args.empty? and (/\Aid[A-Z_]/ =~ event or @var_table.defined?(event))
      event
    else
      "#{ event }(#{ args.map(&:to_s).join(", ") })"
    end
  end

  def self.const_missing(name)
    name
  end
end
