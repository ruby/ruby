# Tiny eRuby --- ERB2
# Copyright (c) 1999-2000,2002,2003 Masatoshi SEKI 
# You can redistribute it and/or modify it under the same terms as Ruby.

class ERB
  Revision = '$Date$' 	#'

  def self.version
    "erb.rb [2.0.4 #{ERB::Revision.split[1]}]"
  end
end

# ERB::Compiler
class ERB
  class Compiler
    class PercentLine
      def initialize(str)
        @value = str
      end
      attr_reader :value
      alias :to_s :value
    end

    class Scanner
      SplitRegexp = /(<%%)|(%%>)|(<%=)|(<%#)|(<%)|(%>)|(\n)/

      def initialize(src)
	@src = src
	@stag = nil
      end
      attr_accessor :stag

      def scan; end
    end

    class TrimScanner < Scanner
      TrimSplitRegexp = /(<%%)|(%%>)|(<%=)|(<%#)|(<%)|(%>\n)|(%>)|(\n)/

      def initialize(src, trim_mode, percent)
	super(src)
	@trim_mode = trim_mode
	@percent = percent
	if @trim_mode
	  @scan_line = self.method(:trim_line)
	else
	  @scan_line = self.method(:scan_line)
	end
      end
      attr_accessor :stag
      
      def scan(&block)
	@stag = nil
	if @percent
	  @src.each do |line|
	    percent_line(line, &block)
	  end
	else
	  @src.each do |line|
	    trim_line(line, &block)
	  end
	end
	nil
      end

      def percent_line(line, &block)
	if @stag || line[0] != ?%
	  return @scan_line.call(line, &block)
	end

	line[0] = ''
	if line[0] == ?%
	  @scan_line.call(line, &block)
	else
          yield(PercentLine.new(line.chomp))
	end
      end

      def scan_line(line)
	line.split(SplitRegexp).each do |token|
	  next if token.empty?
	  yield(token)
	end
      end

      def trim_line(line)
	head = nil
	last = nil
	line.split(TrimSplitRegexp).each do |token|
	  next if token.empty?
	  head = token unless head
	  if token == "%>\n"
	    yield('%>')
	    if @trim_mode == '>' 
	      yield(:cr)
	    elsif  @trim_mode == '<>' && is_erb_stag?(head)
	      yield(:cr)
	    else
	      yield("\n")
	    end
	    break
	  end
	  yield(token)
	end
      end

      ERB_STAG = %w(<%= <%# <%)
      def is_erb_stag?(s)
	ERB_STAG.member?(s)
      end
    end

    class SimpleScanner < Scanner
      def scan
	@src.each do |line|
	  line.split(SplitRegexp).each do |token|
	    next if token.empty?
	    yield(token)
	  end
	end
      end
    end

    class Buffer
      def initialize(compiler)
	@compiler = compiler
	@line = []
	@script = ""
	@compiler.pre_cmd.each do |x|
	  push(x)
	end
      end
      attr_reader :script

      def push(cmd)
	@line << cmd
      end
      
      def cr
	@script << (@line.join('; '))
	@line = []
	@script << "\n"
      end
      
      def close
	return unless @line
	@compiler.post_cmd.each do |x|
	  push(x)
	end
	@script << (@line.join('; '))
	@line = nil
      end
    end

    def compile(s)
      out = Buffer.new(self)

      content = ''
      scanner = make_scanner(s)
      scanner.scan do |token|
	if scanner.stag.nil?
	  case token
          when PercentLine
	    out.push("#{@put_cmd} #{content.dump}") if content.size > 0
	    content = ''
            out.push(token.to_s)
            out.cr
	  when :cr
	    out.cr
	  when '<%', '<%=', '<%#'
	    scanner.stag = token
	    out.push("#{@put_cmd} #{content.dump}") if content.size > 0
	    content = ''
	  when "\n"
	    content << "\n"
	    out.push("#{@put_cmd} #{content.dump}")
	    out.cr
	    content = ''
	  when '<%%'
	    content << '<%'
	  else
	    content << token
	  end
	else
	  case token
	  when '%>'
	    case scanner.stag
	    when '<%'
	      if content[-1] == ?\n
		content.chop!
		out.push(content)
		out.cr
	      else
		out.push(content)
	      end
	    when '<%='
	      out.push("#{@put_cmd}((#{content}).to_s)")
	    when '<%#'
	      # out.push("# #{content.dump}")
	    end
	    scanner.stag = nil
	    content = ''
	  when '%%>'
	    content << '%>'
	  else
	    content << token
	  end
	end
      end
      out.push("#{@put_cmd} #{content.dump}") if content.size > 0
      out.close
      out.script
    end

    def prepare_trim_mode(mode)
      case mode
      when 1
	return [false, '>']
      when 2
	return [false, '<>']
      when 0
	return [false, nil]
      when String
	perc = mode.include?('%')
	if mode.include?('<>')
	  return [perc, '<>']
	elsif mode.include?('>')
	  return [perc, '>']
	else
	  [perc, nil]
	end
      else
	return [false, nil]
      end
    end

    def make_scanner(src)
      if @percent || @trim_mode
	TrimScanner.new(src, @trim_mode, @percent)
      else
	SimpleScanner.new(src)
      end
    end

    def initialize(trim_mode)
      @percent, @trim_mode = prepare_trim_mode(trim_mode)
      @put_cmd = 'print'
      @pre_cmd = []
      @post_cmd = []
    end
    attr_reader :percent, :trim_mode
    attr_accessor :put_cmd, :pre_cmd, :post_cmd
  end
end

# ERB
class ERB
  def initialize(str, safe_level=nil, trim_mode=nil, eoutvar='_erbout')
    @safe_level = safe_level
    compiler = ERB::Compiler.new(trim_mode)
    set_eoutvar(compiler, eoutvar)
    @src = compiler.compile(str)
  end
  attr :src

  def set_eoutvar(compiler, eoutvar = '_erbout')
    compiler.put_cmd = "#{eoutvar}.concat"

    cmd = []
    cmd.push "#{eoutvar} = ''"
    
    compiler.pre_cmd = cmd

    cmd = []
    cmd.push(eoutvar)

    compiler.post_cmd = cmd
  end

  def run(b=TOPLEVEL_BINDING)
    print self.result(b)
  end

  def result(b=TOPLEVEL_BINDING)
    if @safe_level
      th = Thread.start { 
	$SAFE = @safe_level
	eval(@src, b)
      }
      return th.value
    else
      return eval(@src, b)
    end
  end

  def def_method(mod, methodname, fname='(ERB)')
    mod.module_eval("def #{methodname}\n" + self.src + "\nend\n", fname, 0)
  end

  def def_module(methodname='erb')
    mod = Module.new
    def_method(mod, methodname)
    mod
  end

  def def_class(superklass=Object, methodname='result')
    cls = Class.new(superklass)
    def_method(cls, methodname)
    cls
  end
end

# ERB::Util
class ERB
  module Util
    public
    def html_escape(s)
      s.to_s.gsub(/&/, "&amp;").gsub(/\"/, "&quot;").gsub(/>/, "&gt;").gsub(/</, "&lt;")
    end
    alias h html_escape
    
    def url_encode(s)
      s.to_s.gsub(/[^a-zA-Z0-9_\-.]/n){ sprintf("%%%02X", $&.unpack("C")[0]) }
    end
    alias u url_encode
  end
end

# ERB::DefMethod
class ERB
  module DefMethod
    public
    def def_erb_method(methodname, erb)
      if erb.kind_of? String
	fname = erb
	File.open(fname) {|f| erb = ERB.new(f.read) }
	erb.def_method(self, methodname, fname)
      else
	erb.def_method(self, methodname)
      end
    end
    module_function :def_erb_method
  end
end
