class String
  class << self
    attr_reader :str_ivar1

    def str_ivar2
      @str_ivar2
    end
  end

  @str_ivar1 = 111
  @str_ivar2 = 222
end

class StringDelegator < BasicObject
private
  def method_missing(...)
    ::String.public_send(...)
  end
end

StringDelegatorObj = StringDelegator.new
