require 'iSampleStruct'

class SampleStructService
  def hi(struct)
    ack = SampleStruct.new
    ack.wrap(struct)
    ack
  end
end

if __FILE__ == $0
  p SampleStructService.new.hi(SampleStruct.new)
end
