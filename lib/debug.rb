
class DEBUGGER__

  def max(a,b)
    if (a<b); b; else a; end  
  end

  def min(a,b)
    if (a<=b); a; else b; end
  end

  trap("INT") {  DEBUGGER__::CONTEXT.interrupt }
  $DEBUG = TRUE
  def initialize
    @break_points = []
    @stop_next = 1
    @frames = [nil]
    @frame_pos = nil	# nil means not '0' but `unknown'.
    @last_file = nil
    @scripts = {}
  end

  DEBUG_LAST_CMD = []

  def interrupt
    @stop_next = 1
  end

  def debug_eval(str, binding)
    begin
      val = eval(str, binding)
      val
    rescue
      at = caller(0)
      STDOUT.printf "%s:%s\n", at.shift, $!
      for i in at
	break if i =~ /`debug_(eval|command)'$/ #`
	STDOUT.printf "\tfrom %s\n", i
      end
    end
  end

  def debug_command(file, line, id, binding)
    binding_file = file
    binding_line = line
    debug_line = {}
    if (ENV['EMACS'] == 't')
      STDOUT.printf "\032\032%s:%d:\n", binding_file, binding_line
    else
      STDOUT.printf "%s:%d:%s", binding_file, binding_line,
	line_at(binding_file, binding_line)
    end
    @frames[-1] = binding
    STDOUT.print "(rdb:-) "
    STDOUT.flush
    while input = STDIN.gets
      input.chop!
      if input == ""
	input = DEBUG_LAST_CMD[0]
      else
	DEBUG_LAST_CMD[0] = input
      end
      case input

      when /^b(reak)?\s+(([^:\n]+:)?.+)/
	pos = $2
	if pos.index ":"
	  file, pos = pos.split(":")
	end
	file = File.basename(file)
	if pos =~ /^\d+$/
	  pname = pos
	  pos = Integer(pos)
	else
	  pname = pos = pos.intern.id2name
	end
	STDOUT.printf "Set breakpoint %d at %s:%s\n", @break_points.size, file,
	  pname
	@break_points.push [file, pos]

      when /^b(reak)?$/
	n = 0
	for f, p in @break_points
	  STDOUT.printf "%d %s:%s\n", n, f, p
	  n += 1
	end

      when /^del(ete)?(\s+(\d+))?$/
	pos = $3
	unless pos
	  STDOUT.print "clear all breakpoints? (y/n) "
	  STDOUT.flush
	  input = STDIN.gets.chop!
	  if input == "y"
	    for n in @break_points.indexes
	      @break_points[n] = nil
	    end
	  end
	else
	  pos = Integer(pos)
	  if @break_points[pos]
	    bp = @break_points[pos]
	    STDOUT.printf "Clear breakpoint %d at %s:%s\n", pos, bp[0], bp[1]
	    @break_points[pos] = nil
	  else
	    STDOUT.printf "Breakpoint %d is not defined\n", pos
	  end
	end

      when /^c(ont)?$/
	return

      when /^s(tep)?\s*(\d+)?$/
	if $2
	  lev = Integer($2)
	else
	  lev = 1
	end
	@stop_next = lev
	return

      when /^n(ext)?\s*(\d+)?$/
	if $2
	  lev = Integer($2)
	else
	  lev = 1
	end
	@stop_next = lev
	@no_step = @frames.size
	return

      when /^i(?:nfo)?/, /^w(?:here)?/
	fs = @frames.size
	tb = caller(0)[-fs..-1].reverse
	unless @frame_pos; @frame_pos = fs - 1; end

	(fs-1).downto(0){ |i|
	  if (@frame_pos == i)
	    STDOUT.printf "-->  frame %d:%s\n", i, tb[i]
	  else
	    STDOUT.printf "     frame %d:%s\n", i, tb[i]
	  end
	}

      when /^l(ist)?$/
	fs = @frames.size
	tb = caller(0)[-fs..-1].reverse
	unless @frame_pos; @frame_pos = fs - 1; end

	file, line, func = tb[@frame_pos].split(":")
	line = line.to_i
	b = line - 1
	e = line + 9
	line_at(file, line)
	if lines = @scripts[file] and lines != TRUE
	  lines = [0] + lines	# Simple offset adjust
	  b = max(0, b); e = min(lines.size-1, e)
	  for l in b..e
	    if (l == line) 
	      STDOUT.printf "--> %5d %s", l, lines[l]
	    else
	      STDOUT.printf "    %5d %s", l, lines[l]
	    end
	  end
	else
	  STDOUT.printf "no sourcefile available for %s\n", file
	end

      when /^d(?:own)?\s*(\d+)??$/
	if $1; lev = Integer($1); else lev = 1; end
	unless @frame_pos; @frame_pos = 0; end
	@frame_pos -= lev
	if @frame_pos < 0
	  STDOUT.print "at stack bottom\n"
	  @frame_pos = 0
	else
	  STDOUT.printf "at level %d\n", @frame_pos
	end
	binding = @frames[@frame_pos]

      when /^u(?:p)?\s*(\d+)?$/
	if $1; lev = Integer($1); else lev = 1; end
	unless @frame_pos; @frame_pos = @frames.size - 1; end
	@frame_pos += lev
	p @frame_pos
	if @frame_pos >= @frames.size
	  STDOUT.print "at toplevel\n"
	  @frame_pos = nil
	else
	  binding = @frames[@frame_pos]
	  frame_info = caller(4)[-(@frame_pos+1)]
	  STDOUT.print "at #{frame_info}\n"
	  frame_info.sub( /:in `.*'$/, '' ) =~ /^(.*):(\d+)$/ #`
	  binding_file, binding_line = $1, $2.to_i
	  binding = @frames[@frame_pos]
	end

      when /^f(inish)?/
	@finish_pos = @frames.size
	return

      when /^q(uit)?$/
	STDOUT.print "really quit? (y/n) "
	STDOUT.flush
	input = STDIN.gets.chop!
	exit if input == "y"

      when /^p\s+/
	p debug_eval($', binding)

      else
	v = debug_eval(input, binding)
	p v unless v == nil
      end
      STDOUT.print "(rdb:-) "
      STDOUT.flush
    end
  end
  
  def line_at(file, line)
    lines = @scripts[file]
    if lines
      return "\n" if lines == TRUE
      line = lines[line-1]
      return "\n" unless line
      return line
    end
    save = $DEBUG
    begin
      $DEBUG = FALSE
      f = open(file)
      lines = @scripts[file] = f.readlines
    rescue
      $DEBUG = save
      @scripts[file] = TRUE
      return "\n"
    end
    line = lines[line-1]
    return "\n" unless line
    return line
  end

  def debug_funcname(id)
    if id == 0
      "toplevel"
    else
      id.id2name
    end
  end

  def check_break_points(file, pos, binding, id)
    file = File.basename(file)
    if @break_points.include? [file, pos]
      index = @break_points.index([file, pos])
      STDOUT.printf "Breakpoint %d, %s at %s:%s\n",
	index, debug_funcname(id), file, pos
      return TRUE
    end
    return FALSE
  end

  def excn_handle(file, line, id, binding)
    fs = @frames.size
    tb = caller(0)[-fs..-1]
    unless @frame_pos; @frame_pos = fs - 1; end

    STDOUT.printf "%s\n", $!
    for i in tb
      STDOUT.printf "\tfrom %s\n", i
    end
    debug_command(file, line, id, binding)
  end


  def trace_func(event, file, line, id, binding)
    if event == 'line'
      if @no_step == nil or @no_step >= @frames.size
	@stop_next -= 1
      end
      if @stop_next == 0
	if [file, line] == @last
	  @stop_next = 1
	else
	  @no_step = nil
	  debug_command(file, line, id, binding)
	  @last = [file, line]
	end
      end
      if check_break_points(file, line, binding, id)
	debug_command(file, line, id, binding)
      end
    end

    if event == 'call'
      @frames.push binding
      if check_break_points(file, id.id2name, binding, id)
	debug_command(file, line, id, binding)
      end
    end

    if event == 'class'
      @frames.push binding
    end
    
    if event == 'return' or event == 'end'
      if @finish_pos == @frames.size
	@stop_next = 1
      end
      @frames.pop
    end
    
    if event == 'raise' 
      # @frames.push binding
      excn_handle(file, line, id, binding)
    end

    @last_file = file
  end

  CONTEXT = new
end

set_trace_func proc{|event, file, line, id, binding,*rest|
  DEBUGGER__::CONTEXT.trace_func event, file, line, id, binding
}
