#
#   irb/slex.rb - symple lex analizer
#   	$Release Version: 0.7.3$
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(keiju@ishituska.com)
#
# --
#
#   
#

require "e2mmap"

class SLex
  @RCS_ID='-$Id$-'

  extend Exception2MessageMapper
  def_exception :ErrNodeNothing, "node nothing"
  def_exception :ErrNodeAlreadyExists, "node already exists"

  class << self
    attr_accessor :debug_level
    def debug?
      debug_level > 0
    end
  end
  @debug_level = 0

  def initialize
    @head = Node.new("")
  end
  
  def def_rule(token, preproc = nil, postproc = nil)
    #      print node.inspect, "\n" if SLex.debug?
    postproc = proc if iterator?
    node = create(token, preproc, postproc)
  end
  
  def def_rules(*tokens)
    if iterator?
      p = proc
    end
    for token in tokens
      def_rule(token, nil, p)
    end
  end
  
  def preporc(token, proc)
    node = search(token)
    node.preproc=proc
  end
  
  def postproc(token)
    node = search(token, proc)
    node.postproc=proc
  end
  
  def search(token)
    @head.search(token.split(//))
  end

  def create(token, preproc = nil, postproc = nil)
    @head.create_subnode(token.split(//), preproc, postproc)
  end
  
  def match(token)
    case token
    when Array
    when String
      token = token.split(//)
      match(token.split(//))
    else
      return @head.match_io(token)
    end
    ret = @head.match(token)
    printf "match end: %s:%s", ret, token.inspect if SLex.debug?
    ret
  end
  
  def inspect
    format("<SLex: @head = %s>", @head.inspect)
  end

  #----------------------------------------------------------------------
  #
  #   class Node - 
  #
  #----------------------------------------------------------------------
  class Node
    # if postproc no exist, this node is abstract node.
    # if postproc isn't nil, this node is real node.
    # (JP: postprocがなければ抽象ノード, nilじゃなければ具象ノード)
    def initialize(preproc = nil, postproc = nil)
      @Tree = {}
      @preproc = preproc
      @postproc = postproc
    end

    attr_accessor :preproc
    attr_accessor :postproc
    
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
	  SLex.fail ErrNodeNothing
	end
      end
    end
    
    def create_subnode(chrs, preproc = nil, postproc = nil)
      if chrs.empty?
	if @postproc
	  p node
	  SLex.fail ErrNodeAlreadyExists
	else
	  print "Warn: change abstruct node to real node\n" if SLex.debug?
	  @preproc = preproc
	  @postproc = postproc
	end
	return self
      end
      
      ch = chrs.shift
      if node = @Tree[ch]
	if chrs.empty?
	  if node.postproc
	    p node
	    p self
	    p ch
	    p chrs
	    SLex.fail ErrNodeAlreadyExists
	  else
	    print "Warn: change abstruct node to real node\n" if SLex.debug?
	    node.preproc = preproc
	    node.postproc = postproc
	  end
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

    #
    # chrs: String
    #       character array (JP: 一文字づつのArray)
    #       io It must have getc()/ungetc(), and ungetc() can be
    #          called any number of times. 
    #          (JP:だだし, getc/ungetcが備わっていなければならない.
    #           さらに, ungetcは複数回可能でなくてはならない.)
    #
    def match(chrs, op = "")
      print "match>: ", chrs, "op:", op, "\n" if SLex.debug?
      if chrs.empty?
	if @preproc.nil? || @preproc.call(op, chrs)
	  printf "op1: %s\n", op if SLex.debug?
	  @postproc.call(op, chrs)
	else
	  nil
	end
      else
	ch = chrs.shift
	if node = @Tree[ch]
	  if ret = node.match(chrs, op+ch)
	    return ret
	  else
	    chrs.unshift ch
	    if @postproc and @preproc.nil? || @preproc.call(op, chrs)
	      printf "op2: %s\n", op.inspect if SLex.debug?
	      ret = @postproc.call(op, chrs)
	      return ret
	    else
	      return nil
	    end
	  end
	else
	  chrs.unshift ch
	  if @postproc and @preproc.nil? || @preproc.call(op, chrs)
	    printf "op3: %s\n", op if SLex.debug?
	    @postproc.call(op, chrs)
	    return ""
	  else
	    return nil
	  end
	end
      end
    end

    def match_io(io, op = "")
      if op == ""
	ch = io.getc
	if ch == nil
	  return nil
	end
      else
	ch = io.getc_of_rests
      end
      if ch.nil?
	if @preproc.nil? || @preproc.call(op, io)
	  printf "op1: %s\n", op if SLex.debug?
	  @postproc.call(op, io)
	else
	  nil
	end
      else
	if node = @Tree[ch]
	  if ret = node.match_io(io, op+ch)
	    ret
	  else
	    io.ungetc ch
	    if @postproc and @preproc.nil? || @preproc.call(op, io)
	      printf "op2: %s\n", op.inspect if SLex.debug?
	      @postproc.call(op, io)
	    else
	      nil
	    end
	  end
	else
	  io.ungetc ch
	  if @postproc and @preproc.nil? || @preproc.call(op, io)
	    printf "op3: %s\n", op if SLex.debug?
	    @postproc.call(op, io)
	  else
	    nil
	  end
	end
      end
    end
  end
end

if $0 == __FILE__
  #    Tracer.on
  case $1
  when "1"
    tr = SLex.new
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
    tr = SLex.new
    print "0: ", tr.inspect, "\n"
    tr.def_rule("=") {print "=\n"}
    print "1: ", tr.inspect, "\n"
    tr.def_rule("==", proc{false}) {print "==\n"}
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
