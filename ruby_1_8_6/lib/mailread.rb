# The Mail class represents an internet mail message (as per RFC822, RFC2822)
# with headers and a body. 
class Mail

  # Create a new Mail where +f+ is either a stream which responds to gets(),
  # or a path to a file.  If +f+ is a path it will be opened.
  #
  # The whole message is read so it can be made available through the #header,
  # #[] and #body methods.
  #
  # The "From " line is ignored if the mail is in mbox format.
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

  # Return the headers as a Hash.
  def header
    return @header
  end

  # Return the message body as an Array of lines
  def body
    return @body
  end

  # Return the header corresponding to +field+. 
  #
  # Matching is case-insensitive.
  def [](field)
    @header[field.capitalize]
  end
end
