# Simple DSL implementation for Ripper code generation
#
# input: /*% ripper: stmts_add(stmts_new, void_stmt) %*/
# output: $$ = dispatch2(stmts_add, dispatch0(stmts_new), dispatch0(void_stmt))

class DSL
  def initialize(code, options)
    @events = {}
    @error = options.include?("error")
    @brace = options.include?("brace")

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
    s = "\t\t\t#{ s } = #@code;"
    s << "ripper_error(p);" if @error
    s = "{#{ s }}" if @brace
    s
  end

  def method_missing(*args)
    if args.first =~ /\A_/
      "#{ $' }(#{ args.drop(1).join(", ") })"
    else
      @events[args.first.to_s] = args.size - 1
      "dispatch#{ args.size - 1 }(#{ args.join(", ") })"
    end
  end
end

