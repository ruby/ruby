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

    # create $1 == "$1", $2 == "$2", ...
    re, s = "", ""
    1.upto(9) do |n|
      re << "(..)"
      s << "$#{ n }"
    end
    /#{ re }/ =~ s

    # struct parser_params *p
    p = "p"

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
    "\t\t\t#{s}"
  end

  def method_missing(event, *args)
    if event.to_s =~ /!\z/
      event = $`
      @events[event] = args.size
      "dispatch#{ args.size }(#{ [event, *args].join(", ") })"
    elsif args.empty? and /\Aid[A-Z]/ =~ event.to_s
      event
    else
      "#{ event }(#{ args.join(", ") })"
    end
  end

  def self.const_missing(name)
    name
  end
end

