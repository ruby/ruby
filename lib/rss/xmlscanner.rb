require 'xmlscan/scanner'

module RSS
  
  class XMLScanParser < BaseParser
    
    private
    def listener
      XMLScanListener
    end

    def _parse
      begin
        XMLScan::XMLScanner.new(@listener).parse(@rss)
      rescue XMLScan::Error => e
        raise NotWellFormedError.new(e.lineno){e.message}
      end
    end
    
  end

  class XMLScanListener < BaseListener
    
    include XMLScan::Visitor
    include ListenerMixin

    ENTITIES = {
      'lt' => '<',
      'gt' => '>',
      'amp' => '&',
      'quot' => '"',
      'apos' => '\''
    }

    def on_xmldecl_version(str)
      @version = str
    end

    def on_xmldecl_encoding(str)
      @encoding = str
    end

    def on_xmldecl_standalone(str)
      @standalone = str
    end

    def on_xmldecl_end
      xmldecl(@version, @encoding, @standalone == "yes")
    end

    alias_method(:on_pi, :instruction)
    alias_method(:on_chardata, :text)
    alias_method(:on_cdata, :text)

    def on_etag(name)
      tag_end(name)
    end

    def on_entityref(ref)
      text(ENTITIES[ref])
    end

    def on_charref(code)
      text([code].pack('U'))
    end

    alias_method(:on_charref_hex, :on_charref)

    def on_stag(name)
      @attrs = {}
    end

    def on_attribute(name)
      @attrs[name] = @current_attr = ''
    end

    def on_attr_value(str)
      @current_attr << str
    end

    def on_attr_entityref(ref)
      @current_attr << ENTITIES[ref]
    end

    def on_attr_charref(code)
      @current_attr << [code].pack('U')
    end

    alias_method(:on_attr_charref_hex, :on_attr_charref)

    def on_stag_end(name)
      tag_start(name, @attrs)
    end

    def on_stag_end_empty(name)
      tag_start(name, @attrs)
      tag_end(name)
    end

  end

end
