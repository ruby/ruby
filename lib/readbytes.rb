# TruncatedDataError is raised when IO#readbytes fails to read enough data.

class TruncatedDataError<IOError
  def initialize(mesg, data) # :nodoc:
    @data = data
    super(mesg)
  end

  # The read portion of an IO#readbytes attempt.
  attr_reader :data
end

class IO
  # Reads exactly +n+ bytes.
  #
  # If the data read is nil an EOFError is raised.
  #
  # If the data read is too short a TruncatedDataError is raised and the read
  # data is obtainable via its #data method.
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
