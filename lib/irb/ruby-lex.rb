#
#   irb/ruby-lex.rb - ruby lexcal analizer
#   	$Release Version: 0.7.3$
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#
# --
#
#   
#

require "e2mmap"
require "irb/slex"
require "irb/ruby-token"

class RubyLex
  @RCS_ID='-$Id$-'

  extend Exception2MessageMapper
  def_exception(:AlreadyDefinedToken, "Already defined token(%s)")
  def_exception(:TkReading2TokenNoKey, "key nothing(key='%s')")
  def_exception(:TkSymbol2TokenNoKey, "key nothing(key='%s')")
  def_exception(:TkReading2TokenDuplicateError, 
		"key duplicate(token_n='%s', key='%s')")
  def_exception(:SyntaxError, "%s")

  def_exception(:TerminateLineInput, "Terminate Line Input")
  
  include RubyToken

  class << self
    attr_accessor :debug_level
    def debug?
      @debug_level > 0
    end
  end
  @debug_level = 0

  def initialize
    lex_init
    set_input(STDIN)

    @seek = 0
    @exp_line_no = @line_no = 1
    @base_char_no = 0
    @char_no = 0
    @rests = []
    @readed = []
    @here_readed = []

    @indent = 0

    @skip_space = false
    @readed_auto_clean_up = false
    @exception_on_syntax_error = true
  end

  attr_accessor :skip_space
  attr_accessor :readed_auto_clean_up
  attr_accessor :exception_on_syntax_error

  attr_reader :seek
  attr_reader :char_no
  attr_reader :line_no
  attr_reader :indent

  # io functions
  def set_input(io, p = nil)
    @io = io
    if p.kind_of?(Proc)
      @input = p
    elsif iterator?
      @input = proc
    else
      @input = proc{@io.gets}
    end
  end

  def get_readed
    if idx = @readed.reverse.index("\n")
      @base_char_no = idx
    else
      @base_char_no += @readed.size
    end
    
    readed = @readed.join("")
    @readed = []
    readed
  end

  def getc
    while @rests.empty?
      return nil unless buf_input
    end
    c = @rests.shift
    if @here_header
      @here_readed.push c
    else
      @readed.push c
    end
    @seek += 1
    if c == "\n"
      @line_no += 1 
      @char_no = 0
    else
      @char_no += 1
    end
    c
  end

  def gets
    l = ""
    while c = getc
      l.concat c
      break if c == "\n"
    end
    l
  end

  def eof?
    @io.eof?
  end

  def getc_of_rests
    if @rests.empty?
      nil
    else
      getc
    end
  end

  def ungetc(c = nil)
    if @here_readed.empty?
      c2 = @readed.pop
    else
      c2 = @here_readed.pop
    end
    c = c2 unless c
    @rests.unshift c #c = 
      @seek -= 1
    if c == "\n"
      @line_no -= 1 
      if idx = @readed.reverse.index("\n")
	@char_no = @readed.size - idx
      else
	@char_no = @base_char_no + @readed.size
      end
    else
      @char_no -= 1
    end
  end

  def peek_equal?(str)
    chrs = str.split(//)
    until @rests.size >= chrs.size
      return false unless buf_input
    end
    @rests[0, chrs.size] == chrs
  end

  def peek_match?(regexp)
    while @rests.empty?
      return false unless buf_input
    end
    regexp =~ @rests.join("")
  end

  def peek(i = 0)
    while @rests.size <= i
      return nil unless buf_input
    end
    @rests[i]
  end

  def buf_input
    prompt
    line = @input.call
    return nil unless line
    @rests.concat line.split(//)
    true
  end
  private :buf_input

  def set_prompt(p = proc)
    if p.kind_of?(Proc)
      @prompt = p
    else
      @prompt = proc{print p}
    end
  end

  def prompt
    if @prompt
      @prompt.call(@ltype, @indent, @continue, @line_no)
    end
  end

  def initialize_input
    @ltype = nil
    @quoted = nil
    @indent = 0
    @lex_state = EXPR_BEG
    @space_seen = false
    @here_header = false
    
    @continue = false
    prompt

    @line = ""
    @exp_line_no = @line_no
  end
  
  def each_top_level_statement
    initialize_input
    catch(:TERM_INPUT) do
      loop do
	begin
	  @continue = false
	  prompt
	  unless l = lex
	    throw :TERM_INPUT if @line == ''
	  else
	    #p l
	    @line.concat l
	    if @ltype or @continue or @indent > 0
	      next
	    end
	  end
	  if @line != "\n"
	    yield @line, @exp_line_no
	  end
	  break unless l
	  @line = ''
	  @exp_line_no = @line_no

	  @indent = 0
	  prompt
	rescue TerminateLineInput
	  initialize_input
	  prompt
	  get_readed
	end
      end
    end
  end

  def lex
    until (((tk = token).kind_of?(TkNL) || tk.kind_of?(TkEND_OF_SCRIPT)) &&
	     !@continue or
	     tk.nil?)
      #p tk
      #p self
    end
    line = get_readed
    #      print self.inspect
    if line == "" and tk.kind_of?(TkEND_OF_SCRIPT) || tk.nil?
      nil
    else
      line
    end
  end

  def token
    #      require "tracer"
    #      Tracer.on
    @prev_seek = @seek
    @prev_line_no = @line_no
    @prev_char_no = @char_no
    begin
      begin
	tk = @OP.match(self)
	@space_seen = tk.kind_of?(TkSPACE)
      rescue SyntaxError
	abort if @exception_on_syntax_error
	tk = TkError.new(@seek, @line_no, @char_no)
      end
    end while @skip_space and tk.kind_of?(TkSPACE)
    if @readed_auto_clean_up
      get_readed
    end
    #      Tracer.off
    tk
  end
  
  ENINDENT_CLAUSE = [
    "case", "class", "def", "do", "for", "if",
    "module", "unless", "until", "while", "begin" #, "when"
  ]
  DEINDENT_CLAUSE = ["end" #, "when"
  ]

  PERCENT_LTYPE = {
    "q" => "\'",
    "Q" => "\"",
    "x" => "\`",
    "r" => "\/",
    "w" => "]"
  }
  
  PERCENT_PAREN = {
    "{" => "}",
    "[" => "]",
    "<" => ">",
    "(" => ")"
  }

  Ltype2Token = {
    "\'" => TkSTRING,
    "\"" => TkSTRING,
    "\`" => TkXSTRING,
    "\/" => TkREGEXP,
    "]" => TkDSTRING
  }
  DLtype2Token = {
    "\"" => TkDSTRING,
    "\`" => TkDXSTRING,
    "\/" => TkDREGEXP,
  }

  def lex_init()
    @OP = SLex.new
    @OP.def_rules("\0", "\004", "\032") do
      Token(TkEND_OF_SCRIPT)
    end

    @OP.def_rules(" ", "\t", "\f", "\r", "\13") do
      @space_seen = true
      while getc =~ /[ \t\f\r\13]/; end
      ungetc
      Token(TkSPACE)
    end

    @OP.def_rule("#") do
      |op, io|
      identify_comment
    end

    @OP.def_rule("=begin", proc{@prev_char_no == 0 && peek(0) =~ /\s/}) do
      |op, io|
      @ltype = "="
      until getc == "\n"; end
      until peek_equal?("=end") && peek(4) =~ /\s/
	until getc == "\n"; end
      end
      gets
      @ltype = nil
      Token(TkRD_COMMENT)
    end

    @OP.def_rule("\n") do
      print "\\n\n" if RubyLex.debug?
      case @lex_state
      when EXPR_BEG, EXPR_FNAME, EXPR_DOT
	@continue = true
      else
	@continue = false
	@lex_state = EXPR_BEG
      end
      @here_header = false
      @here_readed = []
      Token(TkNL)
    end

    @OP.def_rules("*", "**",	
		  "!", "!=", "!~",
		  "=", "==", "===", 
		  "=~", "<=>",	
		  "<", "<=",
		  ">", ">=", ">>") do
      |op, io|
      @lex_state = EXPR_BEG
      Token(op)
    end

    @OP.def_rules("<<") do
      |op, io|
      if @lex_state != EXPR_END && @lex_state != EXPR_CLASS &&
	  (@lex_state != EXPR_ARG || @space_seen)
	c = peek(0)
	if /\S/ =~ c && (/["'`]/ =~ c || /[\w_]/ =~ c || c == "-")
	  tk = identify_here_document
	end
      else
	tk = 	Token(op)
      end
      tk
    end

    @OP.def_rules("'", '"') do
      |op, io|
      identify_string(op)
    end

    @OP.def_rules("`") do
      |op, io|
      if @lex_state == EXPR_FNAME
	Token(op)
      else
	identify_string(op)
      end
    end

    @OP.def_rules('?') do
      |op, io|
      if @lex_state == EXPR_END
	@lex_state = EXPR_BEG
	Token(TkQUESTION)
      else
	ch = getc
	if @lex_state == EXPR_ARG && ch !~ /\s/
	  ungetc
	  @lex_state = EXPR_BEG;
	  Token(TkQUESTION)
	else
	  if (ch == '\\') 
	    read_escape
	  end
	  @lex_state = EXPR_END
	  Token(TkINTEGER)
	end
      end
    end

    @OP.def_rules("&", "&&", "|", "||") do
      |op, io|
      @lex_state = EXPR_BEG
      Token(op)
    end
    
    @OP.def_rules("+=", "-=", "*=", "**=", 
		  "&=", "|=", "^=", "<<=", ">>=", "||=", "&&=") do
      |op, io|
      @lex_state = EXPR_BEG
      op =~ /^(.*)=$/
      Token(TkOPASGN, $1)
    end

    @OP.def_rule("+@", proc{@lex_state == EXPR_FNAME}) do
      Token(TkUPLUS)
    end

    @OP.def_rule("-@", proc{@lex_state == EXPR_FNAME}) do
      Token(TkUMINUS)
    end

    @OP.def_rules("+", "-") do
      |op, io|
      catch(:RET) do
	if @lex_state == EXPR_ARG
	  if @space_seen and peek(0) =~ /[0-9]/
	    throw :RET, identify_number
	  else
	    @lex_state = EXPR_BEG
	  end
	elsif @lex_state != EXPR_END and peek(0) =~ /[0-9]/
	  throw :RET, identify_number
	else
	  @lex_state = EXPR_BEG
	end
	Token(op)
      end
    end

    @OP.def_rule(".") do
      @lex_state = EXPR_BEG
      if peek(0) =~ /[0-9]/
	ungetc
	identify_number
      else
	# for "obj.if" etc.
	@lex_state = EXPR_DOT
	Token(TkDOT)
      end
    end

    @OP.def_rules("..", "...") do
      |op, io|
      @lex_state = EXPR_BEG
      Token(op)
    end

    lex_int2
  end
  
  def lex_int2
    @OP.def_rules("]", "}", ")") do
      |op, io|
      @lex_state = EXPR_END
      @indent -= 1
      Token(op)
    end

    @OP.def_rule(":") do
      if @lex_state == EXPR_END || peek(0) =~ /\s/
	@lex_state = EXPR_BEG
	Token(TkCOLON)
      else
	@lex_state = EXPR_FNAME;
	Token(TkSYMBEG)
      end
    end

    @OP.def_rule("::") do
#      p @lex_state.id2name, @space_seen
      if @lex_state == EXPR_BEG or @lex_state == EXPR_ARG && @space_seen
	@lex_state = EXPR_BEG
	Token(TkCOLON3)
      else
	@lex_state = EXPR_DOT
	Token(TkCOLON2)
      end
    end

    @OP.def_rule("/") do
      |op, io|
      if @lex_state == EXPR_BEG || @lex_state == EXPR_MID
	identify_string(op)
      elsif peek(0) == '='
	getc
	@lex_state = EXPR_BEG
	Token(TkOPASGN, :/) #/)
      elsif @lex_state == EXPR_ARG and @space_seen and peek(0) !~ /\s/
	identify_string(op)
      else 
	@lex_state = EXPR_BEG
	Token("/") #/)
      end
    end

    @OP.def_rules("^") do
      @lex_state = EXPR_BEG
      Token("^")
    end

    #       @OP.def_rules("^=") do
    # 	@lex_state = EXPR_BEG
    # 	Token(OP_ASGN, :^)
    #       end
    
    @OP.def_rules(",", ";") do
      |op, io|
      @lex_state = EXPR_BEG
      Token(op)
    end

    @OP.def_rule("~") do
      @lex_state = EXPR_BEG
      Token("~")
    end

    @OP.def_rule("~@", proc{@lex_state = EXPR_FNAME}) do
      @lex_state = EXPR_BEG
      Token("~")
    end
    
    @OP.def_rule("(") do
      @indent += 1
      if @lex_state == EXPR_BEG || @lex_state == EXPR_MID
	@lex_state = EXPR_BEG
	Token(TkfLPAREN)
      else
	@lex_state = EXPR_BEG
	Token(TkLPAREN)
      end
    end

    @OP.def_rule("[]", proc{@lex_state == EXPR_FNAME}) do
      Token("[]")
    end

    @OP.def_rule("[]=", proc{@lex_state == EXPR_FNAME}) do
      Token("[]=")
    end

    @OP.def_rule("[") do
      @indent += 1
      if @lex_state == EXPR_FNAME
	Token(TkfLBRACK)
      else
	if @lex_state == EXPR_BEG || @lex_state == EXPR_MID
	  t = Token(TkLBRACK)
	elsif @lex_state == EXPR_ARG && @space_seen
	  t = Token(TkLBRACK)
	else
	  t = Token(TkfLBRACK)
	end
	@lex_state = EXPR_BEG
	t
      end
    end

    @OP.def_rule("{") do
      @indent += 1
      if @lex_state != EXPR_END && @lex_state != EXPR_ARG
	t = Token(TkLBRACE)
      else
	t = Token(TkfLBRACE)
      end
      @lex_state = EXPR_BEG
      t
    end

    @OP.def_rule('\\') do
      if getc == "\n"
	@space_seen = true
	@continue = true
	Token(TkSPACE)
      else
	ungetc
	Token("\\")
      end
    end

    @OP.def_rule('%') do
      |op, io|
      if @lex_state == EXPR_BEG || @lex_state == EXPR_MID
	identify_quotation
      elsif peek(0) == '='
	getc
	Token(TkOPASGN, :%)
      elsif @lex_state == EXPR_ARG and @space_seen and peek(0) !~ /\s/
	identify_quotation
      else
	@lex_state = EXPR_BEG
	Token("%") #))
      end
    end

    @OP.def_rule('$') do
      identify_gvar
    end

    @OP.def_rule('@') do
      if peek(0) =~ /[\w_]/
	ungetc
	identify_identifier
      else
	Token("@")
      end
    end

    #       @OP.def_rule("def", proc{|op, io| /\s/ =~ io.peek(0)}) do 
    # 	|op, io|
    # 	@indent += 1
    # 	@lex_state = EXPR_FNAME
    # #	@lex_state = EXPR_END
    # #	until @rests[0] == "\n" or @rests[0] == ";"
    # #	  rests.shift
    # #	end
    #       end

    @OP.def_rule("") do
      |op, io|
      printf "MATCH: start %s: %s\n", op, io.inspect if RubyLex.debug?
      if peek(0) =~ /[0-9]/
	t = identify_number
      elsif peek(0) =~ /[\w_]/
	t = identify_identifier
      end
      printf "MATCH: end %s: %s\n", op, io.inspect if RubyLex.debug?
      t
    end
    
    p @OP if RubyLex.debug?
  end
  
  def identify_gvar
    @lex_state = EXPR_END
    
    case ch = getc
    when /[~_*$?!@\/\\;,=:<>".]/   #"
      Token(TkGVAR, "$" + ch)
    when "-"
      Token(TkGVAR, "$-" + getc)
    when "&", "`", "'", "+"
      Token(TkBACK_REF, "$"+ch)
    when /[1-9]/
      while getc =~ /[0-9]/; end
      ungetc
      Token(TkNTH_REF)
    when /\w/
      ungetc
      ungetc
      identify_identifier
    else 
      ungetc
      Token("$")
    end
  end
  
  def identify_identifier
    token = ""
    token.concat getc if peek(0) =~ /[$@]/
    while (ch = getc) =~ /\w|_/
      print ":", ch, ":" if RubyLex.debug?
      token.concat ch
    end
    ungetc
    
    if ch == "!" or ch == "?"
      token.concat getc
    end
    # almost fix token

    case token
    when /^\$/
      return Token(TkGVAR, token)
    when /^\@/
      @lex_state = EXPR_END
      return Token(TkIVAR, token)
    end
    
    if @lex_state != EXPR_DOT
      print token, "\n" if RubyLex.debug?

      token_c, *trans = TkReading2Token[token]
      if token_c
	# reserved word?

	if (@lex_state != EXPR_BEG &&
	    @lex_state != EXPR_FNAME &&
	    trans[1])
	  # modifiers
	  token_c = TkSymbol2Token[trans[1]]
	  @lex_state = trans[0]
	else
	  if @lex_state != EXPR_FNAME
	    if ENINDENT_CLAUSE.include?(token)
	      @indent += 1
	    elsif DEINDENT_CLAUSE.include?(token)
	      @indent -= 1
	    end
	    @lex_state = trans[0]
	  else
	    @lex_state = EXPR_END
	  end
	end
	return Token(token_c, token)
      end
    end

    if @lex_state == EXPR_FNAME
      @lex_state = EXPR_END
      if peek(0) == '='
	token.concat getc
      end
    elsif @lex_state == EXPR_BEG || @lex_state == EXPR_DOT
      @lex_state = EXPR_ARG
    else
      @lex_state = EXPR_END
    end

    if token[0, 1] =~ /[A-Z]/
      return Token(TkCONSTANT, token)
    elsif token[token.size - 1, 1] =~ /[!?]/
      return Token(TkFID, token)
    else
      return Token(TkIDENTIFIER, token)
    end
  end

  def identify_here_document
    ch = getc
#    if lt = PERCENT_LTYPE[ch]
    if ch == "-"
      ch = getc
      indent = true
    end
    if /['"`]/ =~ ch
      lt = ch
      quoted = ""
      while (c = getc) && c != lt
	quoted.concat c
      end
    else
      lt = '"'
      quoted = ch.dup
      while (c = getc) && c =~ /\w/
	quoted.concat c
      end
      ungetc
    end

    ltback, @ltype = @ltype, lt
    reserve = []
    while ch = getc
      reserve.push ch
      if ch == "\\"
	reserve.push ch = getc
      elsif ch == "\n"
	break
      end
    end

    @here_header = false
    while (l = gets.chomp) && (indent ? l.strip : l) != quoted
    end

    @here_header = true
    @here_readed.concat reserve
    while ch = reserve.pop
      ungetc ch
    end

    @ltype = ltback
    @lex_state = EXPR_END
    Token(Ltype2Token[lt])
  end
  
  def identify_quotation
    ch = getc
    if lt = PERCENT_LTYPE[ch]
      ch = getc
    elsif ch =~ /\W/
      lt = "\""
    else
      RubyLex.fail SyntaxError, "unknown type of %string"
    end
#     if ch !~ /\W/
#       ungetc
#       next
#     end
    #@ltype = lt
    @quoted = ch unless @quoted = PERCENT_PAREN[ch]
    identify_string(lt, @quoted)
  end

  def identify_number
    @lex_state = EXPR_END

    if ch = getc
      if peek(0) == "x"
	ch = getc
	match = /[0-9a-f_]/
      else
	match = /[0-7_]/
      end
      while ch = getc
	if ch !~ match
	  ungetc
	  break
	end
      end
      return Token(TkINTEGER)
    end
    
    type = TkINTEGER
    allow_point = true
    allow_e = true
    while ch = getc
      case ch
      when /[0-9_]/
      when allow_point && "."
	type = TkFLOAT
	if peek(0) !~ /[0-9]/
	  ungetc
	  break
	end
	allow_point = false
      when allow_e && "e", allow_e && "E"
	type = TkFLOAT
	if peek(0) =~ /[+-]/
	  getc
	end
	allow_e = false
	allow_point = false
      else
	ungetc
	break
      end
    end
    Token(type)
  end
  
  def identify_string(ltype, quoted = ltype)
    @ltype = ltype
    @quoted = quoted
    subtype = nil
    begin
      while ch = getc 
	if @quoted == ch
	  break
	elsif @ltype != "'" && @ltype != "]" and ch == "#"
	  subtype = true
	elsif ch == '\\' #'
	  read_escape
	end
      end
      if @ltype == "/"
	if peek(0) =~ /i|o|n|e|s/
	  getc
	end
      end
      if subtype
	Token(DLtype2Token[ltype])
      else
	Token(Ltype2Token[ltype])
      end
    ensure
      @ltype = nil
      @quoted = nil
      @lex_state = EXPR_END
    end
  end
  
  def identify_comment
    @ltype = "#"

    while ch = getc
      if ch == "\\" #"
	read_escape
      end
      if ch == "\n"
	@ltype = nil
	ungetc
	break
      end
    end
    return Token(TkCOMMENT)
  end
  
  def read_escape
    case ch = getc
    when "\n", "\r", "\f"
    when "\\", "n", "t", "r", "f", "v", "a", "e", "b" #"
    when /[0-7]/
      ungetc ch
      3.times do
	case ch = getc
	when /[0-7]/
	when nil
	  break
	else
	  ungetc
	  break
	end
      end
      
    when "x"
      2.times do
	case ch = getc
	when /[0-9a-fA-F]/
	when nil
	  break
	else
	  ungetc
	  break
	end
      end

    when "M"
      if (ch = getc) != '-'
	ungetc
      else
	if (ch = getc) == "\\" #"
	  read_escape
	end
      end

    when "C", "c", "^"
      if ch == "C" and (ch = getc) != "-"
	ungetc
      elsif (ch = getc) == "\\" #"
	read_escape
      end
    else
      # other characters 
    end
  end
end
