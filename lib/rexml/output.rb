require 'rexml/encoding'

module REXML
  class Output
    include Encoding

    attr_reader :encoding

    def initialize real_IO, encd="iso-8859-1"
      @output = real_IO
      self.encoding = encd

      @to_utf = encd == UTF_8 ? false : true
    end

    def <<( content )
      @output << (@to_utf ? self.encode(content) : content)
    end

    def to_s
      "Output[#{encoding}]"
    end
  end
end
