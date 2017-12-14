class Gem::StringSink
  def initialize
    @string = ""
  end

  attr_reader :string

  def write(s)
    @string += s
    s.size
  end

  def set_encoding(enc)
    @string.force_encoding enc
  end
end

class Gem::StringSource
  def initialize(str)
    @string = str.dup
  end

  def read(count=nil)
    if count
      @string.slice!(0,count)
    else
      s = @string
      @string = ""
      s
    end
  end

  alias_method :readpartial, :read
end
