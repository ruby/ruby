class DEBUGGER__
  begin
    require 'readline'
    def readline(prompt, hist)
      Readline::readline(prompt, hist)
    end
  rescue LoadError
    def readline(prompt, hist)
      STDOUT.print prompt
      STDOUT.flush
      line = STDIN.gets
      line.chomp!
      line
    end
    USE_READLINE = false
  end

  trap("INT") {  DEBUGGER__::CONTEXT.interrupt }
  $DEBUG = true
  def initialize
    @break_points = []
    @display = []
    @stop_next = 1
    @frames = [nil]
    @last_file = nil
    @last = [nil, nil]
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
    frame_pos = 0
    binding_file = file
    binding_line = line
    previus_line = nil
    if (ENV['EMACS'] == 't')
      STDOUT.printf "\032\032%s:%d:\n", binding_file, binding_line
    else
      STDOUT.printf "%s:%d:%s", binding_file, binding_line,
	line_at(binding_file, binding_line)
    end
    @frames[0] = binding
    display_expressions(binding)
    while input = readline("(rdb:-) ", true)
      if input == ""
	input = DEBUG_LAST_CMD[0]
      else
	DEBUG_LAST_CMD[0] = input
      end

      case input
      when /^b(?:reak)?\s+((?:[^:\n]+:)?.+)/
	pos = $1
	if pos.index(":")
	  file, pos = pos.split(":")
	end
	file = File.basename(file)
	if pos =~ /^\d+$/
	  pname = pos
	  pos = pos.to_i
	else
	  pname = pos = pos.intern.id2name
	end
	@break_points.push [true, 0, file, pos]
	STDOUT.printf "Set breakpoint %d at %s:%s\n", @break_points.size, file,
	  pname

      when /^wat(?:ch)?\s+((?:[^:\n]+:)?.+)$/
	exp = $1
	@break_points.push [true, 1, exp]
	STDOUT.printf "Set watchpoint %d\n", @break_points.size, exp

      when /^b(?:reak)?$/, /^info b(?:reak)?$/
	n = 1
	STDOUT.print "breakpoints:\n"
	for b in @break_points
	  if b[0] and (b[1] == 0)
	    STDOUT.printf "  %d %s:%s\n", n, b[2], b[3] 
	  end
	  n += 1
	end
	n = 1
	STDOUT.print "\n"
	STDOUT.print "watchpoints:\n"
	for b in @break_points
	  if b[0] and (b[1] == 1)
	    STDOUT.printf "  %d %s\n", n, b[2]
	  end
	  n += 1
	end
	STDOUT.print "\n"

      when /^del(?:ete)?(?:\s+(\d+))?$/
	pos = $1
	unless pos
	  input = readline("clear all breakpoints? (y/n) ", false)
	  if input == "y"
	    for b in @break_points
	      b[0] = false
	    end
	  end
	else
	  pos = pos.to_i
	  if @break_points[pos-1]
	    @break_points[pos-1][0] = false
	  else
	    STDOUT.printf "Breakpoint %d is not defined\n", pos
	  end
	end

      when /^disp(?:lay)?\s+(.+)$/
	exp = $1
	@display.push.push [true, exp]
	STDOUT.printf "  %d: %s = %s\n", @display.size, exp,
	  debug_eval(exp, binding).to_s

      when /^disp(?:lay)?$/, /^info disp(?:lay)?$/
	display_expressions(binding)

      when /^undisp(?:lay)?(?:\s+(\d+))?$/
	pos = $1
	unless pos
	  input = readline("clear all expressions? (y/n) ", false)
	  if input == "y"
	    for d in @display
	      d[0] = false
	    end
	  end
	else
	  pos = pos.to_i
	  if @display[pos-1]
	    @display[pos-1][0] = false
	  else
	    STDOUT.printf "display expression %d is not defined\n", pos
	  end
	end

      when /^co(?:nt)?$/
	return

      when /^s(?:tep)?\s*(\d+)?$/
	if $1
	  lev = $1.to_i
	else
	  lev = 1
	end
	@stop_next = lev
	return

      when /^n(?:ext)?\s*(\d+)?$/
	if $1
	  lev = $1.to_i
	else
	  lev = 1
	end
	@stop_next = lev
	@no_step = @frames.size - frame_pos
	return

      when /^w(?:here)?$/, /^f(?:rame)?$/
	at = caller(0)
	0.upto(@frames.size - 1) do |n|
	  if frame_pos == n
	    STDOUT.printf "--> #%d  %s\n", n, at[-(@frames.size - n)]
	  else
	    STDOUT.printf "    #%d  %s\n", n, at[-(@frames.size - n)]
	  end
	end

      when /^l(?:ist)?(?:\s+(.+))?$/
        if not $1
          b = previus_line ? previus_line + 10 : binding_line - 5
          e = b + 9
        elsif $1 == '-'
          b = previus_line ? previus_line - 10 : binding_line - 5
          e = b + 9
        else
          b, e = $1.split(/[-,]/)
          if e
            b = b.to_i
            e = e.to_i
          else
            b = b.to_i - 5
            e = b + 9
          end
        end
        previus_line = b
        STDOUT.printf "[%d, %d] in %s\n", b, e, binding_file
        line_at(binding_file, binding_line)
        if lines = @scripts[binding_file] and lines != true
          n = 0
          b.upto(e) do |n|
            if n > 0 && lines[n-1]
	      if n == binding_line
              	STDOUT.printf "=> %d  %s\n", n, lines[n-1].chomp
	      else
              	STDOUT.printf "   %d  %s\n", n, lines[n-1].chomp
	      end
            end
          end
        else
          STDOUT.printf "no sourcefile available for %s\n", binding_file
        end

      when /^up\s*(\d+)?$/
	previus_line = nil
        if $1
          lev = $1.to_i
        else
          lev = 1
        end
        frame_pos += lev
        if frame_pos >= @frames.size
	  frame_pos = @frames.size - 1
          STDOUT.print "at toplevel\n"
	end
        binding = @frames[frame_pos]
        info, binding_file, binding_line = frame_info(frame_pos)
        STDOUT.printf "#%d %s\n", frame_pos, info

      when /^down\s*(\d+)?$/
	previus_line = nil
        if $1
          lev = $1.to_i
        else
          lev = 1
        end
        frame_pos -= lev
        if frame_pos < 0
          frame_pos = 0
          STDOUT.print "at stack bottom\n"
	end
        binding = @frames[frame_pos]
        info, binding_file, binding_line = frame_info(frame_pos)
        STDOUT.printf "#%d %s\n", frame_pos, info

      when /^fi(?:nish)?$/
	@finish_pos = @frames.size - frame_pos
	frame_pos = 0
	return

      when /^q(?:uit)?$/
	input = readline("really quit? (y/n) ", false)
	exit if input == "y"

      when /^p\s+/
	p debug_eval($', binding)

      else
	v = debug_eval(input, binding)
	p v unless (v == nil)
      end
    end
  end
  
  def display_expressions(binding)
    n = 1
    for d in @display
      if d[0]
      	STDOUT.printf "%d: %s = %s\n", n, d[1], debug_eval(d[1], binding).to_s
      end
      n += 1
    end
  end

  def frame_info(pos = 0)
    info = caller(0)[-(@frames.size - pos)]
    info.sub(/:in `.*'$/, "") =~ /^(.*):(\d+)$/ #`
    [info, $1, $2.to_i]
  end

  def line_at(file, line)
    lines = @scripts[file]
    if lines
      return "\n" if lines == true
      line = lines[line-1]
      return "\n" unless line
      return line
    end
    save = $DEBUG
    begin
      $DEBUG = false
      f = open(file)
      lines = @scripts[file] = f.readlines
    rescue
      $DEBUG = save
      @scripts[file] = true
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
    n = 1
    for b in @break_points
      if b[0]
	if b[1] == 0 and b[2] == file and b[3] == pos
      	  STDOUT.printf "breakpoint %d, %s at %s:%s\n", n, debug_funcname(id),
	    file, pos
      	  return true
	elsif b[1] == 1 and debug_eval(b[2], binding)
      	  STDOUT.printf "watchpoint %d, %s at %s:%s\n", n, debug_funcname(id),
	    file, pos
      	  return true
      	end
      end
      n += 1
    end
    return false
  end

  def excn_handle(file, line, id, binding)
    fs = @frames.size
    tb = caller(0)[-fs..-1]

    STDOUT.printf "%s\n", $!
    for i in tb
      STDOUT.printf "\tfrom %s\n", i
    end
    debug_command(file, line, id, binding)
  end

  def trace_func(event, file, line, id, binding)
    case event
    when 'line'
      if !@no_step or @frames.size == @no_step
	@stop_next -= 1
      elsif @frames.size < @no_step
	@stop_next = 0		# break here before leaving...
      else
	# nothing to do. skipped.
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

    when 'call'
      @frames.unshift binding
      if check_break_points(file, id.id2name, binding, id)
	debug_command(file, line, id, binding)
      end

    when 'class'
      @frames.unshift binding
    
    when 'return', 'end'
      if @frames.size == @finish_pos
	@stop_next = 1
      end
      @frames.shift
    
    when 'raise' 
      excn_handle(file, line, id, binding)

    end
    @last_file = file
  end

  CONTEXT = new
end

set_trace_func proc{|event, file, line, id, binding,*rest|
  DEBUGGER__::CONTEXT.trace_func event, file, line, id, binding
}
