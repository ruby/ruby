#
# intp
#

class Intp::Parser

prechigh
  nonassoc UMINUS
  left     '*' '/'
  left     '+' '-'
  nonassoc EQ
preclow

rule

  program   : stmt_list
                {
                  result = RootNode.new( val[0] )
                }

  stmt_list :
                {
                  result = []
                }
            | stmt_list stmt EOL
                {
                  result.push val[1]
                }
            | stmt_list EOL
  
  stmt      : expr
            | assign
            | IDENT realprim
                {
                  result = FuncallNode.new( @fname, val[0][0],
                                            val[0][1], [val[1]] )
                }
            | if_stmt
            | while_stmt
            | defun
  
  if_stmt   : IF stmt THEN EOL stmt_list else_stmt END
                {
                  result = IfNode.new( @fname, val[0][0],
                                       val[1], val[4], val[5] )
                }

  else_stmt : ELSE EOL stmt_list
                {
                  result = val[2]
                }
            |
                {
                  result = nil
                }

  while_stmt: WHILE stmt DO EOL stmt_list END
                {
                  result = WhileNode.new(@fname, val[0][0],
                                          val[1], val[4])
                }

  defun     : DEF IDENT param EOL stmt_list END
                {
                  result = DefNode.new(@fname, val[0][0], val[1][1],
                      Function.new(@fname, val[0][0], val[2], val[4]))
                }

  param     : '(' name_list ')'
                {
                  result = val[1]
                }
            | '(' ')'
                {
                  result = []
                }
            |
                {
                  result = []
                }

  name_list : IDENT
                {
                  result = [ val[0][1] ]
                }
            | name_list ',' IDENT
                {
                  result.push val[2][1]
                }

  assign    : IDENT '=' expr
                {
                  result = AssignNode.new(@fname, val[0][0], val[0][1], val[2])
                }

  expr      : expr '+' expr
                {
                  result = FuncallNode.new(@fname, val[0].lineno, '+', [val[0], val[2]])
                }
            | expr '-' expr
                {
                  result = FuncallNode.new(@fname, val[0].lineno, '-', [val[0], val[2]])
                }
            | expr '*' expr
                {
                  result = FuncallNode.new(@fname, val[0].lineno, '*', [val[0], val[2]])
                }
            | expr '/' expr
                {
                  result = FuncallNode.new(@fname, val[0].lineno,
                                            '/', [val[0], val[2]])
                }
            | expr EQ expr
                {
                  result = FuncallNode.new(@fname, val[0].lineno, '==', [val[0], val[2]])
                }
            | primary

  primary   : realprim
            | '(' expr ')'
                {
                  result = val[1]
                }
            | '-' expr  =UMINUS
                {
                  result = FuncallNode.new(@fname, val[0][0], '-@', [val[1]])
                }

  realprim  : IDENT
                {
                  result = VarRefNode.new(@fname, val[0][0],
                                           val[0][1])
                }
            | NUMBER
                {
                  result = LiteralNode.new(@fname, *val[0])
                }
            | STRING
                {
                  result = StringNode.new(@fname, *val[0])
                }
            | TRUE
                {
                  result = LiteralNode.new(@fname, *val[0])
                }
            | FALSE
                {
                  result = LiteralNode.new(@fname, *val[0])
                }
            | NIL
                {
                  result = LiteralNode.new(@fname, *val[0])
                }
            | funcall

  funcall   : IDENT '(' args ')'
                {
                  result = FuncallNode.new(@fname, val[0][0], val[0][1], val[2])
                }
            | IDENT '(' ')'
                {
                  result = FuncallNode.new(@fname, val[0][0], val[0][1], [])
                }

  args      : expr
                {
                  result = val
                }
            | args ',' expr
                {
                  result.push val[2]
                }

end

---- header
#
# intp/parser.rb
#

---- inner

  def initialize
    @scope = {}
  end

  RESERVED = {
    'if'    => :IF,
    'else'  => :ELSE,
    'while' => :WHILE,
    'then'  => :THEN,
    'do'    => :DO,
    'def'   => :DEF,
    'true'  => :TRUE,
    'false' => :FALSE,
    'nil'   => :NIL,
    'end'   => :END
  }

  RESERVED_V = {
    'true'  => true,
    'false' => false,
    'nil'   => nil
  }

  def parse(f, fname)
    @q = []
    @fname = fname
    lineno = 1
    f.each do |line|
      line.strip!
      until line.empty?
        case line
        when /\A\s+/, /\A\#.*/
          ;
        when /\A[a-zA-Z_]\w*/
          word = $&
          @q.push [(RESERVED[word] || :IDENT),
                   [lineno, RESERVED_V.key?(word) ? RESERVED_V[word] : word.intern]]
        when /\A\d+/
          @q.push [:NUMBER, [lineno, $&.to_i]]
        when /\A"(?:[^"\\]+|\\.)*"/, /\A'(?:[^'\\]+|\\.)*'/
          @q.push [:STRING, [lineno, eval($&)]]
        when /\A==/
          @q.push [:EQ, [lineno, '==']]
        when /\A./
          @q.push [$&, [lineno, $&]]
        else
          raise RuntimeError, 'must not happen'
        end
        line = $'
      end
      @q.push [:EOL, [lineno, nil]]
      lineno += 1
    end
    @q.push [false, '$']
    do_parse
  end

  def next_token
    @q.shift
  end

  def on_error(t, v, values)
    if v
      line = v[0]
      v = v[1]
    else
      line = 'last'
    end
    raise Racc::ParseError, "#{@fname}:#{line}: syntax error on #{v.inspect}"
  end

---- footer
# intp/node.rb

module Intp

  class IntpError < StandardError; end
  class IntpArgumentError < IntpError; end

  class Core

    def initialize 
      @ftab = {}
      @obj = Object.new
      @stack = []
      @stack.push Frame.new '(toplevel)'
    end

    def frame
      @stack[-1]
    end

    def define_function(fname, node)
      raise IntpError, "function #{fname} defined twice" if @ftab.key?(fname)
      @ftab[fname] = node
    end

    def call_function_or(fname, args)
      call_intp_function_or(fname, args) {
        call_ruby_toplevel_or(fname, args) {
          yield
        }
      }
    end

    def call_intp_function_or(fname, args)
      if func = @ftab[fname]
        frame = Frame.new(fname)
        @stack.push frame
        func.call self, frame, args
        @stack.pop
      else
        yield
      end
    end

    def call_ruby_toplevel_or(fname, args)
      if @obj.respond_to? fname, true
        @obj.send fname, *args
      else
        yield
      end
    end

  end

  class Frame

    def initialize(fname)
      @fname = fname
      @lvars = {}
    end

    attr :fname

    def lvar?(name)
      @lvars.key? name
    end
    
    def [](key)
      @lvars[key]
    end

    def []=(key, val)
      @lvars[key] = val
    end

  end


  class Node

    def initialize(fname, lineno)
      @filename = fname
      @lineno = lineno
    end

    attr_reader :filename
    attr_reader :lineno

    def exec_list(intp, nodes)
      v = nil
      nodes.each {|i| v = i.evaluate(intp) }
      v
    end

    def intp_error!(msg)
      raise IntpError, "in #{filename}:#{lineno}: #{msg}"
    end

    def inspect
      "#{self.class.name}/#{lineno}"
    end

  end


  class RootNode < Node

    def initialize(tree)
      super nil, nil
      @tree = tree
    end

    def evaluate
      exec_list Core.new, @tree
    end

  end


  class DefNode < Node

    def initialize(file, lineno, fname, func)
      super file, lineno
      @funcname = fname
      @funcobj = func
    end

    def evaluate(intp)
      intp.define_function @funcname, @funcobj
    end

  end

  class FuncallNode < Node

    def initialize(file, lineno, func, args)
      super file, lineno
      @funcname = func
      @args = args
    end

    def evaluate(intp)
      args = @args.map {|i| i.evaluate intp }
      begin
        intp.call_intp_function_or(@funcname, args) {
          if args.empty? or not args[0].respond_to?(@funcname)
            intp.call_ruby_toplevel_or(@funcname, args) {
              intp_error! "undefined function #{@funcname.id2name}"
            }
          else
            recv = args.shift
            recv.send @funcname, *args
          end
        }
      rescue IntpArgumentError, ArgumentError
        intp_error! $!.message
      end
    end

  end

  class Function < Node

    def initialize(file, lineno, params, body)
      super file, lineno
      @params = params
      @body = body
    end

    def call(intp, frame, args)
      unless args.size == @params.size
        raise IntpArgumentError,
          "wrong # of arg for #{frame.fname}() (#{args.size} for #{@params.size})"
      end
      args.each_with_index do |v,i|
        frame[@params[i]] = v
      end
      exec_list intp, @body
    end

  end


  class IfNode < Node

    def initialize(fname, lineno, cond, tstmt, fstmt)
      super fname, lineno
      @condition = cond
      @tstmt = tstmt
      @fstmt = fstmt
    end

    def evaluate(intp)
      if @condition.evaluate(intp)
        exec_list intp, @tstmt
      else
        exec_list intp, @fstmt if @fstmt
      end
    end

  end

  class WhileNode < Node

    def initialize(fname, lineno, cond, body)
      super fname, lineno
      @condition = cond
      @body = body
    end

    def evaluate(intp)
      while @condition.evaluate(intp)
        exec_list intp, @body
      end
    end

  end


  class AssignNode < Node

    def initialize(fname, lineno, vname, val)
      super fname, lineno
      @vname = vname
      @val = val
    end

    def evaluate(intp)
      intp.frame[@vname] = @val.evaluate(intp)
    end

  end

  class VarRefNode < Node

    def initialize(fname, lineno, vname)
      super fname, lineno
      @vname = vname
    end

    def evaluate(intp)
      if intp.frame.lvar?(@vname)
        intp.frame[@vname]
      else
        intp.call_function_or(@vname, []) {
          intp_error! "unknown method or local variable #{@vname.id2name}"
        }
      end
    end

  end

  class StringNode < Node

    def initialize(fname, lineno, str)
      super fname, lineno
      @val = str
    end

    def evaluate(intp)
      @val.dup
    end

  end

  class LiteralNode < Node

    def initialize(fname, lineno, val)
      super fname, lineno
      @val = val
    end

    def evaluate(intp)
      @val
    end

  end

end   # module Intp

begin
  tree = nil
  fname = 'src.intp'
  File.open(fname) {|f|
    tree = Intp::Parser.new.parse(f, fname)
  }
  tree.evaluate
rescue Racc::ParseError, Intp::IntpError, Errno::ENOENT
  raise ####
  $stderr.puts "#{File.basename $0}: #{$!}"
  exit 1
end
