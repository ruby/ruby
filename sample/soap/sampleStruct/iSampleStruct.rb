require 'soap/mapping'

SampleStructServiceNamespace = 'http://tempuri.org/sampleStructService'

class SampleStruct; include SOAP::Marshallable
  attr_accessor :sampleArray
  attr_accessor :date

  def initialize
    @sampleArray = SampleArray[ "cyclic", self ]
    @date = DateTime.now
  end

  def wrap( rhs )
    @sampleArray = SampleArray[ "wrap", rhs.dup ]
    @date = DateTime.now
    self
  end
end

class SampleArray < Array; include SOAP::Marshallable
end
