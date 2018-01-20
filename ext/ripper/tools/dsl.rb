# Simple DSL implementation for Ripper code generation
#
# input: /*% ripper: stmts_add(stmts_new, void_stmt) %*/
# output: $$ = dispatch2(stmts_add, dispatch0(stmts_new), dispatch0(void_stmt))

class DSL
  def initialize(code, options)
    @events = {}
    @error = options.include?("error")
    @brace = options.include?("brace")
    @final = options.include?("final")
    @var_field_1 = options.include?("var_field_1")

    # create $1 == "$1", $2 == "$2", ...
    re, s = "", ""
    1.upto(9) do |n|
      re << "(..)"
      s << "$#{ n }"
    end
    /#{ re }/ =~ s

    @code = eval(code)
  end

  attr_reader :events

  undef lambda
  undef hash
  undef class

  def generate
    s = "$$"
    s = "p->result" if @final
    s = "#{ s } = #@code;"
    s << "ripper_error(p);" if @error
    s = "{#{ s }}" if @brace
    s = "$1 = var_field(p, $1);" + s if @var_field_1
    "\t\t\t#{s}"
  end

  def method_missing(event, *args)
    if event.to_s =~ /!\z/
      event = $`
      @events[event] = args.size
      "dispatch#{ args.size }(#{ [event, *args].join(", ") })"
    else
      "#{ event }(#{ args.join(", ") })"
    end
  end
end

