class Mail
  def Mail.new(f)
    unless f.kind_of?(IO)
      f = open(f, "r")
      me = super(f)
      f.close
    else
      me = super
    end
    return me
  end

  def initialize(f)
    @header = {}
    @body = []
    while f.gets()
      $_.chop!
      next if /^From /		# skip From-line
      break if /^$/		# end of header

      if /^(\S+):\s*(.*)/
	@header[attr = $1.capitalize!] = $2
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
  end

  def header
    return @header
  end

  def body
    return @body
  end

  def [](field)
    @header[field]
  end
end
