#!/usr/local/bin/ruby
#
#   rbc.rb - 
#   	$Release Version: 0.6 $
#   	$Revision: 1.2 $
#   	$Date: 1997/11/27 13:46:06 $
#   	by Keiju ISHITSUKA(Nippon Rational Inc.)
#
# --
# Usage:
#
#   rbc.rb [options] file_name opts
#   options:
#	-d		    デバッグモード(利用しない方が良いでしょう)
#	-m		    bcモード(分数, 行列の計算ができます)
#	-r load-module	    ruby -r と同じ
#	--inspect	    結果出力にinspectを用いる(bcモード以外はデ
#			    フォルト). 
#	--noinspect	    結果出力にinspectを用いない.
#	--noreadline	    readlineライブラリを利用しない(デフォルト
#			    ではreadlineライブラリを利用しようとする).
#
# 追加 private method:
#   exit, quit		    終了する.
#   inspect(sw = nil)	    インスペクトモードのトグル
#   trace_load(sw = nil)    load/require時にrbcのfile読み込み機能を用
#			    いるモードのスイッチ(デフォルトはトレース
#			    モード)
#
require "e2mmap.rb"

$stdout.sync = TRUE

module BC_APPLICATION__
  RCS_ID='-$Header: /home/keiju/var/src/var.lib/ruby/ruby/RCS/rbc.rb,v 1.2 1997/11/27 13:46:06 keiju Exp keiju $-'
  
  extend Exception2MessageMapper
  def_exception :UnrecognizedSwitch, "Unrecognized switch: %s"
  
  $DEBUG = FALSE
  $INSPECT = nil
  
  CONFIG = {}
  CONFIG[0] = $0
  CONFIG[:USE_READLINE] = TRUE
  CONFIG[:LOAD_MODULES] = []
  CONFIG[:INSPECT] = nil
  CONFIG[:TRACE_LOAD] = TRUE

  while opt = ARGV.shift
    case opt
    when "-d"
      $DEBUG = TRUE
    when "-m"
      CONFIG[:INSPECT] = FALSE if CONFIG[:INSPECT].nil?
      require "mathn.rb"
      include Math
    when "-r"
      opt = ARGV.shift
      CONFIG[:LOAD_MODULES].push opt if opt
    when "--inspect"
      CONFIG[:INSPECT] = TRUE
    when "--noinspect"
      CONFIG[:INSPECT] = FALSE
    when "--noreadline"
      CONFIG[:USE_READLINE] = FALSE
    when /^-/
      #	  print UnrecognizedSwitch.inspect, "\n"
      BC.fail UnrecognizedSwitch, opt
    else
      CONFIG[:USE_READLINE] = FALSE
      $0 = opt
      break
    end
  end
  CONFIG[:INSPECT] = TRUE if CONFIG[:INSPECT].nil?

  PROMPTi = "rbc%d> "
  PROMPTs = "rbc%d%s "
  PROMPTe = "rbc%d* "
  
  class BC
    def initialize
      lex_init
    end
    
    def eval_input(io, cont, bind)
      line = ''
      @io = io
      @ltype = nil
      @quoted = nil
      @indent = 0
      @lex_state = EXPR_BEG
      
      @io.prompt = format(PROMPTi, @indent)

      loop do
	@continue = FALSE
	l = @io.gets

	unless l
	  break if line == ''
	else
	  line = line + l
	  
	  lex(l) if l != "\n"
	  print @quoted.inspect, "\n" if $DEBUG
	  if @ltype
	    @io.prompt = format(PROMPTs, @indent, @ltype)
	    next
	  elsif @continue
	    @io.prompt = format(PROMPTe, @indent)
	    next
	  elsif @indent > 0
	    @io.prompt = format(PROMPTi, @indent)
	    next
	  end
	end
	
	if line != "\n"
	  begin
	    if CONFIG[:INSPECT]
	      print (cont._=eval(line, bind)).inspect, "\n"
	    else
	      print (cont._=eval(line, bind)), "\n"
	    end
	  rescue
	    #	$! = 'exception raised' unless $!
	    #	print "ERR: ", $!, "\n"
	    $! = RuntimeError.new("exception raised") unless $!
	    print $!.type, ": ", $!, "\n"
	  end
	end
	break if not l
	line = ''
	indent = 0
	@io.prompt = format(PROMPTi, indent)
      end
      print "\n"
    end
    
    EXPR_BEG = :EXPR_BEG
    EXPR_MID = :EXPR_MID
    EXPR_END = :EXPR_END
    EXPR_ARG = :EXPR_ARG
    EXPR_FNAME = :EXPR_FNAME

    CLAUSE_STATE_TRANS = {
      "alias"	=>  EXPR_FNAME,
      "and"	=>  EXPR_BEG,
      "begin"	=>  EXPR_BEG,
      "case"	=>  EXPR_BEG,
      "class"	=>  EXPR_BEG,
      "def"	=>  EXPR_FNAME,
      "defined?"	=>  EXPR_END,
      "do"	=>  EXPR_BEG,
      "else"	=>  EXPR_BEG,
      "elsif"	=>  EXPR_BEG,
      "end"	=>  EXPR_END,
      "ensure"	=>  EXPR_BEG,
      "for"	=>  EXPR_BEG,
      "if"	=>  EXPR_BEG,
      "in"	=>  EXPR_BEG,
      "module"	=>  EXPR_BEG,
      "nil"	=>  EXPR_END,
      "not"	=>  EXPR_BEG,
      "or"	=>  EXPR_BEG,
      "rescue"	=>  EXPR_MID,
      "return"	=>  EXPR_MID,
      "self"	=>  EXPR_END,
      "super"	=>  EXPR_END,
      "then"	=>  EXPR_BEG,
      "undef"	=>  EXPR_FNAME,
      "unless"	=>  EXPR_BEG,
      "until"	=>  EXPR_BEG,
      "when"	=>  EXPR_BEG,
      "while"	=>  EXPR_BEG,
      "yield"	=>  EXPR_END
    }
    
    ENINDENT_CLAUSE = [
      "case", "class", "def", "do", "for", "if",
      "module", "unless", "until", "while", "begin" #, "when"
    ]
    DEINDENT_CLAUSE = ["end"]

    PARCENT_LTYPE = {
      "q" => "\'",
      "Q" => "\"",
      "x" => "\`",
      "r" => "\/"
    }
    
    PARCENT_PAREN = {
      "{" => "}",
      "[" => "]",
      "<" => ">",
      "(" => ")"
    }
    
    def lex_init()
      @OP = Trie.new
      @OP.def_rules("\0", "\004", "\032"){}
      @OP.def_rules(" ", "\t", "\f", "\r", "\13") do
	@space_seen = TRUE
	next
      end
      @OP.def_rule("#") do
	|op, rests|
	@ltype = "#"
	identify_comment(rests)
      end
      @OP.def_rule("\n") do
	print "\\n\n" if $DEBUG
	if @lex_state == EXPR_BEG || @lex_state == EXPR_FNAME
	  @continue = TRUE
	else
	  @lex_state = EXPR_BEG
	end
      end
      @OP.def_rules("*", "*=", "**=", "**") {@lex_state = EXPR_BEG}
      @OP.def_rules("!", "!=", "!~") {@lex_state = EXPR_BEG}
      @OP.def_rules("=", "==", "===", "=~", "=>") {@lex_state = EXPR_BEG}
      @OP.def_rules("<", "<=", "<=>", "<<", "<=") {@lex_state = EXPR_BEG}
      @OP.def_rules(">", ">=", ">>", ">=") {@lex_state = EXPR_BEG}
      @OP.def_rules("'", '"') do
	|op, rests|
	@ltype = op
	@quoted = op
	identify_string(rests)
      end
      @OP.def_rules("`") do
	|op, rests|
	if @lex_state != EXPR_FNAME
	  @ltype = op
	  @quoted = op
	  identify_string(rests)
	end
      end
      @OP.def_rules('?') do
	|op, rests|
	@lex_state = EXPR_END
	identify_question(rests)
      end
      @OP.def_rules("&", "&&", "&=", "|", "||", "|=") do
	@lex_state = EXPR_BEG
      end
      @OP.def_rule("+@", proc{@lex_state == EXPR_FNAME}) {}
      @OP.def_rule("-@", proc{@lex_state == EXPR_FNAME}) {}
      @OP.def_rules("+=", "-=") {@lex_state = EXPR_BEG}
      @OP.def_rules("+", "-") do
	|op, rests|
	if @lex_state == EXPR_ARG
	  if @space_seen and rests[0] =~ /[0-9]/
	    identify_number(rests)
	  else
	    @lex_state = EXPR_BEG
	  end
	elsif @lex_state != EXPR_END and rests[0] =~ /[0-9]/
	  identify_number(rests)
	else
	  @lex_state = EXPR_BEG
	end
      end
      @OP.def_rule(".") do
	|op, rests|
	@lex_state = EXPR_BEG
	if rests[0] =~ /[0-9]/
	  rests.unshift op
	  identify_number(rests)
	end
      end
      @OP.def_rules("..", "...") {@lex_state = EXPR_BEG}
      
      lex_int2
    end
    
    def lex_int2
      @OP.def_rules("]", "}", ")") do
	@lex_state = EXPR_END
	@indent -= 1
      end
      @OP.def_rule(":") {}
      @OP.def_rule("::") {@lex_state = EXPR_BEG}
      @OP.def_rule("/") do
	|op, rests|
	if @lex_state == EXPR_BEG || @lex_state == EXPR_MID
	  @ltype = op
	  @quoted = op
	  identify_string(rests)
	elsif rests[0] == '='
	  rests.shift
	  @lex_state = EXPR_BEG
	elsif @lex_state == EXPR_ARG and @space_seen and rests[0] =~ /\s/
	  @ltype = op
	  @quoted = op
	  identify_string(rests)
	else 
	  @lex_state = EXPR_BEG
	end
      end
      @OP.def_rules("^", "^=") {@lex_state = EXPR_BEG}
      @OP.def_rules(",", ";") {@lex_state = EXPR_BEG}
      @OP.def_rule("~") {@lex_state = EXPR_BEG}
      @OP.def_rule("~@", proc{@lex_state = EXPR_FNAME}) {}
      @OP.def_rule("(") do
	@lex_state = EXPR_BEG
	@indent += 1
      end
      @OP.def_rule("[]", proc{@lex_state == EXPR_FNAME}) {}
      @OP.def_rule("[]=", proc{@lex_state == EXPR_FNAME}) {}
      @OP.def_rule("[") do
	@indent += 1
	if @lex_state != EXPR_FNAME
	  @lex_state = EXPR_BEG
	end
      end
      @OP.def_rule("{") do
	@lex_state = EXPR_BEG
	@indent += 1
      end
      @OP.def_rule('\\') {|op, rests| identify_escape(rests)} #')
      @OP.def_rule('%') do
	|op, rests|
	if @lex_state == EXPR_BEG || @lex_state == EXPR_MID
	  identify_quotation(rests)
	elsif rests[0] == '='
	  rests.shift
	elsif @lex_state == EXPR_ARG and @space_seen and rests[0] =~ /\s/
	  identify_quotation(rests)
	else
	  @lex_state = EXPR_BEG
	end
      end
      @OP.def_rule('$') do
	|op, rests|
	identify_gvar(rests)
      end
      @OP.def_rule('@') do
	|op, rests|
	if rests[0] =~ /[\w_]/
	  rests.unshift op
	  identify_identifier(rests)
	end
      end
      @OP.def_rule("") do
	|op, rests|
	printf "match: start %s: %s", op, rests.inspect if $DEBUG
	if rests[0] =~ /[0-9]/
	  identify_number(rests)
	elsif rests[0] =~ /[\w_]/
	  identify_identifier(rests)
	end
	printf "match: end %s: %s", op, rests.inspect if $DEBUG
      end
    end
    
    def lex(l)
      chrs = l.split(//)
      tokens = []
      
      case @ltype
      when "'", '"', '`', '/'
	identify_string(chrs)
	return if chrs.empty?
      when "#"
	identify_comment(chrs)
	return
      when "="
	if l =~ /^=end/
	  $ltype = nil
	  return
	end
      else
	if l =~ /^=begin/
	  $ltype = "="
	  return
	end
      end
      
      until chrs.empty?
	@space_seen = FALSE
	printf "perse: %s\n", chrs.join("") if $DEBUG
	@OP.match(chrs)
	printf "lex_state: %s continue: %s\n", @lex_state.id2name, @continue if $DEBUG
      end
    end
    
    def identify_gvar(chrs)
      @lex_state = EXPR_END
      
      ch = chrs.shift
      case ch
      when /[_~*$?!@/\\;,.=:<>"]/   #"
	return
	
      when "-"
	ch = chrs.shift
	return
	
      when "&", "`", "'", "+"
	return
	
      when /[1-9]/
	chrs.unshift ch
	v = "$"
	while (ch = chrs.shift) =~ /[0-9]/
	end
	chrs.unshift ch
	return
	
      when /\w/
	chrs.unshift ch
	chrs.unshift "$"
	identify_identifier(chrs)
	return
	
      else 
	chrs.unshift ch
	return
      end
    end
    
    def identify_identifier(chrs)
      token = ""
      token.concat chrs.shift if chrs[0] =~ /[$@]/
      while (ch = chrs.shift) =~ /\w|_/
	print ":", ch, ":" if $DEBUG
	token.concat ch
      end
      chrs.unshift ch
      
      if ch == "!" or ch == "?"
	chrs.shift
	token.concat ch
      end
      # fix token
      
      if token =~ /^[$@]/
	@lex_state = EXPR_END
	return
      end
      
      print token, "\n" if $DEBUG
      if state = CLAUSE_STATE_TRANS[token]
	if @lex_state != EXPR_BEG and token =~ /^(if|unless|while|until)/
	  # 修飾子
	else
	  if ENINDENT_CLAUSE.include?(token)
	    @indent += 1
	  elsif DEINDENT_CLAUSE.include?(token)
	    @indent -= 1
	  end
	end
	@lex_state = state
	return
      end
      if @lex_state == EXPR_FNAME
	@lex_state = EXPR_END
	if chrs[0] == '='
	  chrs.shift
	end
      elsif @lex_state == EXPR_BEG
	@lex_state = EXPR_ARG
      else
	@lex_state = EXPR_END
      end
    end
    
    def identify_quotation(chrs)
      ch = chrs.shift
      if lt = PARCENT_LTYPE[ch]
	ch = chrs.shift
      else
	lt = "\""
      end
      if ch !~ /\W/
	chrs.unshift ch
	next
      end
      @ltype = lt
      unless @quoted = PARCENT_PAREN[ch]
	@quoted = ch
      end
      identify_string(chrs)
    end

    def identify_number(chrs)
      @lex_state = EXPR_END
      
      ch = chrs.shift
      case ch
      when /0/
	if (ch = chrs[0]) == "x"
	  chrs.shift
	  match = /[0-9a-f_]/
	else
	  match = /[0-7_]/
	end
	while ch = chrs.shift
	  if ch !~ match
	    chrs.unshift ch
	    break
	  end
	end
	return
      end
      
      while ch = chrs.shift
	case ch
	when /[0-9]/
	when "e", "E"
	  #	type = FLOAT
	  unless (ch = chrs.shift) == "+" or ch == "-"
	    chrs.unshift ch
	  end
	when "."
	  #	type = FLOAT
	when "_"
	else
	  chrs.unshift ch
	  return
	end
      end
    end
    
    def identify_question(chrs)
      @lex_state = EXPR_END
      
      if chrs.shift == "\\" #"
	identify_escape(chrs)
      end
    end
    
    def identify_string(chrs)
      while ch = chrs.shift
	if @quoted == ch
	  if @ltype == "/"
	    if chrs[0] =~ /i|o|n|e|s/
	      chrs.shift
	    end
	  end
	  @ltype = nil
	  @quoted = nil
	  @lex_state = EXPR_END
	  break
	elsif ch == '\\' #'
	  identify_escape(chrs)
	end
      end
    end
    
    def identify_comment(chrs)
      while ch = chrs.shift
	if ch == "\\" #"
	  identify_escape(chrs)
	end
	if ch == "\n"
	  @ltype = nil
	  chrs.unshift ch
	  break
	end
      end
    end
    
    def identify_escape(chrs)
      ch = chrs.shift
      case ch
      when "\n", "\r", "\f"
	@continue = TRUE
      when "\\", "n", "t", "r", "f", "v", "a", "e", "b" #"
      when /[0-7]/
	chrs.unshift ch
	3.times do
	  ch = chrs.shift
	  case ch
	  when /[0-7]/
	  when nil
	    break
	  else
	    chrs.unshift ch
	    break
	  end
	end
      when "x"
	2.times do
	  ch = chrs.shift
	  case ch
	  when /[0-9a-fA-F]/
	  when nil
	    break
	  else
	    chrs.unshift ch
	    break
	  end
	end
      when "M"
	if (ch = chrs.shift) != '-'
	  chrs.unshift ch
	elsif (ch = chrs.shift) == "\\" #"
	  identify_escape(chrs)
	end
	return
      when "C", "c", "^"
	if ch == "C" and (ch = chrs.shift) != "-"
	  chrs.unshift ch
	elsif (ch = chrs.shift) == "\\" #"
	  identify_escape(chrs)
	end
	return
      end
    end
  end
  
  class Trie
    extend Exception2MessageMapper
    def_exception :ErrNodeNothing, "node nothing"
    def_exception :ErrNodeAlreadyExists, "node already exists"

    class Node
      # postprocがなければ抽象ノード, nilじゃなければ具象ノード
      def initialize(preproc = nil, postproc = nil)
	@Tree = {}
	@preproc = preproc
	@postproc = postproc
      end
      
      def preproc(p)
	@preproc = p
      end
      
      def postproc(p)
	@postproc = p
      end
      
      def search(chrs, opt = nil)
	return self if chrs.empty?
	ch = chrs.shift
	if node = @Tree[ch]
	  node.search(chrs, opt)
	else
	  if opt
	    chrs.unshift ch
	    self.create_subnode(chrs)
	  else
	    Trie.fail ErrNodeNothing
	  end
	end
      end
      
      def create_subnode(chrs, preproc = nil, postproc = nil)
	ch = chrs.shift
	if node = @Tree[ch]
	  if chrs.empty?
	    Trie.fail ErrNodeAlreadyExists
	  else
	    node.create_subnode(chrs, preproc, postproc)
	  end
	else
	  if chrs.empty?
	    node = Node.new(preproc, postproc)
	  else
	    node = Node.new
	    node.create_subnode(chrs, preproc, postproc)
	  end
	  @Tree[ch] = node
	end
	node
      end
      
      def match(chrs, op = "")
	print "match: ", chrs, ":", op, "\n" if $DEBUG
	if chrs.empty?
	  if @preproc.nil? || @preproc.call(op, chrs)
	    printf "op1: %s\n", op if $DEBUG
	    @postproc.call(op, chrs)
	    ""
	  else
	    nil
	  end
	else
	  ch = chrs.shift
	  if node = @Tree[ch]
	    if ret = node.match(chrs, op+ch)
	      return ch+ret
	    elsif @postproc and @preproc.nil? || @preproc.call(op, chrs)
	      chrs.unshift ch
	      printf "op2: %s\n", op if $DEBUG
	      @postproc.call(op, chrs)
	      return ""
	    else
	      chrs.unshift ch
	      return nil
	    end
	  else
	    if @postproc and @preproc.nil? || @preproc.call(op, chrs)
	      printf "op3: %s\n", op if $DEBUG
	      chrs.unshift ch
	      @postproc.call(op, chrs)
	      return ""
	    else
	      chrs.unshift ch
	      return nil
	    end
	  end
	end
      end
    end
    
    def initialize
      @head = Node.new("")
    end
    
    def def_rule(token, preproc = nil, postproc = nil)
      node = search(token, :CREATE)
#      print node.inspect, "\n" if $DEBUG
      node.preproc(preproc)
      if iterator?
	node.postproc(proc)
      elsif postproc
	node.postproc(postproc)
      end
    end
    
    def def_rules(*tokens)
      if iterator?
	p = proc
      end
      for token in tokens
	def_rule(token, nil, p)
      end
    end
    
    def preporc(token)
      node = search(token)
      node.preproc proc
    end
    
    def postproc(token)
      node = search(token)
      node.postproc proc
    end
    
    def search(token, opt = nil)
      @head.search(token.split(//), opt)
    end
    
    def match(token)
      token = token.split(//) if token.kind_of?(String)
      ret = @head.match(token)
      printf "match end: %s:%s", ret, token.inspect if $DEBUG
      ret
    end
    
    def inspect
      format("<Trie: @head = %s>", @head.inspect)
    end
  end
  
  if /^-tt(.*)$/ =~ ARGV[0]
#    Tracer.on
    case $1
    when "1"
      tr = Trie.new
      print "0: ", tr.inspect, "\n"
      tr.def_rule("=") {print "=\n"}
      print "1: ", tr.inspect, "\n"
      tr.def_rule("==") {print "==\n"}
      print "2: ", tr.inspect, "\n"
      
      print "case 1:\n"
      print tr.match("="), "\n"
      print "case 2:\n"
      print tr.match("=="), "\n"
      print "case 3:\n"
      print tr.match("=>"), "\n"
      
    when "2"
      tr = Trie.new
      print "0: ", tr.inspect, "\n"
      tr.def_rule("=") {print "=\n"}
      print "1: ", tr.inspect, "\n"
      tr.def_rule("==", proc{FALSE}) {print "==\n"}
      print "2: ", tr.inspect, "\n"
      
      print "case 1:\n"
      print tr.match("="), "\n"
      print "case 2:\n"
      print tr.match("=="), "\n"
      print "case 3:\n"
      print tr.match("=>"), "\n"
    end
    exit
  end
  
  module CONTEXT
    def _=(value)
      @_ = value
    end
    
    def _
      @_
    end
    
    def quit
      exit
    end
    
    def trace_load(opt = nil)
      if opt
	@Trace_require = opt
      else
	@Trace_require = !@Trace_require
      end
      print "Switch to load/require #{unless @Trace_require; ' non';end} trace mode.\n"
      if @Trace_require
	eval %{
	  class << self
	    alias load rbc_load
	    alias require rbc_require
	  end
	}
      else
	eval %{
	  class << self
	    alias load rbc_load_org
	    alias require rbc_require_org
	  end
	}
      end
      @Trace_require
    end
    
    alias rbc_load_org load
    def rbc_load(file_name)
      return true if load_sub(file_name)
      raise LoadError, "No such file to load -- #{file_name}"
    end

    alias rbc_require_org require
    def rbc_require(file_name)
      rex = Regexp.new("#{Regexp.quote(file_name)}(\.o|\.rb)?")
      return false if $".find{|f| f =~ rex}

      case file_name
      when /\.rb$/
	if load_sub(file_name)
	  $:.push file_name
	  return true
	end
      when /\.(so|o|sl)$/
	require_org(file_name)
      end
      
      if load_sub(f = file_name + ".rb")
	  $:.push f
      end
      require(file_name)
    end

    def load_sub(fn)
      if fn =~ /^#{Regexp.quote(File::Separator)}/
	return false unless File.exist?(fn)
	BC.new.eval_input FileInputMethod.new(fn), self, CONFIG[:BIND]
	return true
      end
      
      for path in $:
	if File.exist?(f = File.join(path, fn))
	  BC.new.eval_input FileInputMethod.new(f), self, CONFIG[:BIND]
	  return true
	end
      end
      return false
    end

    def inspect(opt = nil)
      if opt
	CONFIG[:INSPECT] = opt
      else
	CONFIG[:INSPECT] = !$INSPECT
      end
      print "Switch to#{unless $INSPECT; ' non';end} inspect mode.\n"
      $INSPECT
    end
    
    def run
      CONFIG[:BIND] = proc

      if CONFIG[:TRACE_LOAD]
	trace_load true
      end
  
      for m in CONFIG[:LOAD_MODULES]
	begin
	  require m
	rescue
	  print $@[0], ":", $!.type, ": ", $!, "\n"
	end
      end
  
      if !$0.equal?(CONFIG[0])
	io = FileInputMethod.new($0)
      elsif defined? Readline
	io = ReadlineInputMethod.new
      else
	io = StdioInputMethod.new
      end

      BC.new.eval_input io, self, CONFIG[:BIND]
    end
  end
  
  class InputMethod
    attr :prompt, TRUE
    
    def gets
    end
    public :gets
  end
  
  class StdioInputMethod < InputMethod
    def gets
      print @prompt
      $stdin.gets
    end
  end
  
  class FileInputMethod < InputMethod
    def initialize(file)
      @io = open(file)
    end

    def gets
      l = @io.gets
      print @prompt, l
      l
    end
  end

  if CONFIG[:USE_READLINE]
    begin
      require "readline"
      print "use readline module\n"
      class ReadlineInputMethod < InputMethod
	include Readline 
	def gets
	  if l = readline(@prompt, TRUE)
	    l + "\n"
	  else
	    l
	  end
	end
      end
    rescue
      CONFIG[:USE_READLINE] = FALSE
    end
  end
end

extend BC_APPLICATION__::CONTEXT
run{}
