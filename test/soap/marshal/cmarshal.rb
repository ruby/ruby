module CMarshal
  class << self
  public
    def ruby
      class << self
	def dump(o)
	  Marshal.dump(o)
	end
  
   	def load(o)
    	  Marshal.load(o)
     	end
      end
    end

    def amarshal
      require 'amarshal'
      class << self
	def dump(o)
	  AMarshal.dump(o)
	end
  
   	def load(o)
    	  AMarshal.load(o)
     	end
      end
    end
  
    def to_src
      require 'to_src'
      ToSrc.independent(false)
      class << self
      	def dump(o)
       	  ToSrc.reset
  	  o.to_src
   	end
  
   	def load(o)
  	  eval(o)
   	end
      end
    end
  
    def to_source
      require 'ToSource'
      class << self
      	def dump(o)
  	  o.to_source
   	end
  
   	def load(o)
  	  eval(o)
   	end
      end
    end

    class ClXmlSerialContainer
      attr_accessor :var
    end

    def clxmlserial
      require 'cl/xmlserial'
      ClXmlSerialContainer.instance_eval { include XmlSerialization }
      class << self
      	def dump(o)
          c = ClXmlSerialContainer.new
          c.var = o
          c.to_xml
   	end
  
   	def load(o)
          ClXmlSerialContainer.from_xml(o).var
   	end
      end
    end

    def soap4r
      require 'soap/marshal'
      class << self
      	def dump(o)
       	  SOAP::Marshal.dump(o)
	end
  
   	def load(o)
  	  SOAP::Marshal.load(o)
   	end
      end
    end
  
    def xmarshal
      require 'xmarshal'
      class << self
      	def dump(o)
  	  XMarshal.dump(o)
   	end
  
   	def load(o)
  	  XMarshal.load(o)
   	end
      end
    end
  
    def xmlrpc
      require 'xmlrpc/marshal'
      class << self
      	def dump(o)
  	  XMLRPC::Marshal.dump(o)
   	end
  
   	def load(o)
  	  XMLRPC::Marshal.load(o)
   	end
      end
    end
  
    def tmarshal
      require 'tmarshal'
      class << self
      	def dump(o)
  	  TMarshal.dump(o)
   	end
  
   	def load(o)
  	  TMarshal.restore(o)
   	end
      end
    end
  
    def yaml
      require 'yaml'
      class << self
      	def dump(o)
  	  o.to_yaml
   	end
  
   	def load(o)
  	  YAML.load(o)
   	end
      end
    end
  end
end
