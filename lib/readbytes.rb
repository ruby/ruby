# readbytes.rb
#
# add IO#readbytes, which reads fixed sized data.
# it guarantees read data size.

class TruncatedDataError<IOError
  def initialize(mesg, data)
    @data = data
    super(mesg)
  end
  attr_reader :data
end

class IO
  def readbytes(n)
    str = read(n)
    if str == nil
      raise EOFError, "End of file reached"
    end
    if str.size < n
      raise TruncatedDataError.new("data truncated", str) 
    end
    str
  end
end

if __FILE__ == $0
  begin
    loop do
      print STDIN.readbytes(6)
    end
  rescue TruncatedDataError
    p $!.data
    raise
  end
end
