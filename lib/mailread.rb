class Mail

  def initialize(f)
    unless defined? f.gets
      f = open(f, "r")
      opened = true
    end

    @header = {}
    @body = []
    begin
      while f.gets()
	$_.chop!
	next if /^From /	# skip From-line
	break if /^$/		# end of header

	if /^(\S+):\s*(.*)/
	  (attr = $1).capitalize!
	  @header[attr] = $2
	elsif attr
	  sub!(/^\s*/, '')
	  @header[attr] += "\n" + $_
	end
      end
  
      return unless $_

      while f.gets()
	break if /^From /
	@body.push($_)
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
