class Mail

  def initialize(f)
    unless defined? f.gets
      f = open(f, "r")
      opened = true
    end

    @header = {}
    @body = []
    begin
      while line = f.gets()
	line.chop!
	next if /^From /=~line	# skip From-line
	break if /^$/=~line	# end of header

	if /^(\S+?):\s*(.*)/=~line
	  (attr = $1).capitalize!
	  @header[attr] = $2
	elsif attr
	  line.sub!(/^\s*/, '')
	  @header[attr] += "\n" + line
	end
      end
  
      return unless line

      while line = f.gets()
	break if /^From /=~line
	@body.push(line)
      end
    ensure
      f.close if opened
    end
  end

  def header
    return @header
  end

  def body
    return @body
  end

  def [](field)
    @header[field.capitalize]
  end
end
