# Simple DSL implementation for Ripper code generation
#
# input: /*% ripper: stmts_add(stmts_new, void_stmt) %*/
# output:
#   VALUE v1, v2;
#   v1 = dispatch0(stmts_new);
#   v2 = dispatch0(void_stmt);
#   $$ = dispatch2(stmts_add, v1, v2);

class DSL
  def initialize(code, options)
    @events = {}
    @error = options.include?("error")
    @brace = options.include?("brace")
    if options.include?("final")
      @final = "p->result"
    else
      @final = (options.grep(/\A\$(?:\$|\d+)\z/)[0] || "$$")
    end
    @vars = 0

    # create $1 == "$1", $2 == "$2", ...
    s = (1..20).map {|n| "$#{n}"}
    re = Array.new(s.size, "([^\0]+)")
    /#{re.join("\0")}/ =~ s.join("\0")

    # struct parser_params *p
    p = p = "p"

    @code = ""
    @last_value = eval(code)
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
    "\t\t\t#{s}"
  end

  def new_var
    "v#{ @vars += 1 }"
  end

  def opt_event(event, default, addend)
    add_event(event, [default, addend], true)
  end

  def add_event(event, args, qundef_check = false)
    event = event.to_s.sub(/!\z/, "")
    @events[event] = args.size
    vars = []
    args.each do |arg|
      vars << v = new_var
      @code << "#{ v }=#{ arg };"
    end
    v = new_var
    d = "dispatch#{ args.size }(#{ [event, *vars].join(",") })"
    d = "#{ vars.last }==Qundef ? #{ vars.first } : #{ d }" if qundef_check
    @code << "#{ v }=#{ d };"
    v
  end

  def method_missing(event, *args)
    if event.to_s =~ /!\z/
      add_event(event, args)
    elsif args.empty? and /\Aid[A-Z_]/ =~ event.to_s
      event
    else
      "#{ event }(#{ args.join(", ") })"
    end
  end

  def self.const_missing(name)
    name
  end
end

