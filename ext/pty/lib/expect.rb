$expect_verbose = false

class IO
  def expect(pat,timeout=9999999)
    buf = ''
    case pat
    when String
      e_pat = Regexp.new(Regexp.quote(pat))
    when Regexp
      e_pat = pat
    end
    while true
      if IO.select([self],nil,nil,timeout).nil? then
        result = nil
        break
      end
      c = getc.chr
      buf << c
      if $expect_verbose
        STDOUT.print c
        STDOUT.flush
      end
      if buf =~ e_pat then
        result = [buf,$1,$2,$3,$4,$5,$6,$7,$8,$9]
        break
      end
    end
    if iterator? then
      yield result
    else
      return result
    end
    nil
  end
end

