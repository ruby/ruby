# -*- tab-width: 2 -*- vim: ts=2

require "test/unit"
require 'rss-assertions'

module RSS
  class TestCase < Test::Unit::TestCase

    include RSS
    include Assertions

    XMLDECL_VERSION = "1.0"
    XMLDECL_ENCODING = "UTF-8"
    XMLDECL_STANDALONE = "no"

    RDF_ABOUT = "http://www.xml.com/xml/news.rss"
    RDF_RESOURCE = "http://xml.com/universal/images/xml_tiny.gif"
    TITLE_VALUE = "XML.com"
    LINK_VALUE = "http://xml.com/pub"
    URL_VALUE = "http://xml.com/universal/images/xml_tiny.gif"
    NAME_VALUE = "hogehoge"
    LANGUAGE_VALUE = "ja"
    DESCRIPTION_VALUE = "
    XML.com features a rich mix of information and services 
    for the XML community.
    "
    RESOURCES = [
      "http://xml.com/pub/2000/08/09/xslt/xslt.html",
      "http://xml.com/pub/2000/08/09/rdfdb/index.html",
    ]

    CLOUD_DOMAIN = "data.ourfavoritesongs.com"
    CLOUD_PORT = "80"
    CLOUD_PATH = "/RPC2"
    CLOUD_REGISTER_PROCEDURE = "ourFavoriteSongs.rssPleaseNotify"
    CLOUD_PROTOCOL = "xml-rpc"
    
    ENCLOSURE_URL = "http://www.scripting.com/mp3s/weatherReportSuite.mp3"
    ENCLOSURE_LENGTH = "12216320"
    ENCLOSURE_TYPE = "audio/mpeg"
    
    CATEGORY_DOMAIN = "http://www.superopendirectory.com/"

    def default_test
      # This class isn't tested
    end

    private
    def make_xmldecl(v=XMLDECL_VERSION, e=XMLDECL_ENCODING, s=XMLDECL_STANDALONE)
      rv = "<?xml version='#{v}'"
      rv << " encoding='#{e}'" if e
      rv << " standalone='#{s}'" if s
      rv << "?>"
      rv
    end

    def make_RDF(content=nil, xmlns=[])
      <<-EORSS
#{make_xmldecl}
<rdf:RDF xmlns="#{URI}" xmlns:rdf="#{RDF::URI}"
#{xmlns.collect {|pre, uri| "xmlns:#{pre}='#{uri}'"}.join(' ')}>
#{block_given? ? yield : content}
</rdf:RDF>
EORSS
    end

    def make_channel(content=nil)
      <<-EOC
<channel rdf:about="#{RDF_ABOUT}">
  <title>#{TITLE_VALUE}</title>
  <link>#{LINK_VALUE}</link>
  <description>#{DESCRIPTION_VALUE}</description>

  <image rdf:resource="#{RDF_RESOURCE}" />

  <items>
    <rdf:Seq>
#{RESOURCES.collect do |res| '<rdf:li resource="' + res + '" />' end.join("\n")}
    </rdf:Seq>
  </items>

  <textinput rdf:resource="#{RDF_RESOURCE}" />

#{block_given? ? yield : content}
</channel>
EOC
    end

    def make_image(content=nil)
      <<-EOI
<image rdf:about="#{RDF_ABOUT}">
  <title>#{TITLE_VALUE}</title>
  <url>#{URL_VALUE}</url>
  <link>#{LINK_VALUE}</link>
#{block_given? ? yield : content}
</image>
EOI
    end

    def make_item(content=nil)
      <<-EOI
<item rdf:about="#{RDF_ABOUT}">
  <title>#{TITLE_VALUE}</title>
  <link>#{LINK_VALUE}</link>
  <description>#{DESCRIPTION_VALUE}</description>
#{block_given? ? yield : content}
</item>
EOI
    end

    def make_textinput(content=nil)
      <<-EOT
<textinput rdf:about="#{RDF_ABOUT}">
  <title>#{TITLE_VALUE}</title>
  <description>#{DESCRIPTION_VALUE}</description>
  <name>#{NAME_VALUE}</name>
  <link>#{LINK_VALUE}</link>
#{block_given? ? yield : content}
</textinput>
EOT
    end

    def make_sample_RDF
      make_RDF(<<-EOR)
#{make_channel}
#{make_image}
#{make_item}
#{make_textinput}
EOR
    end

    def make_rss20(content=nil, xmlns=[])
      <<-EORSS
#{make_xmldecl}
<rss version="2.0"
#{xmlns.collect {|pre, uri| "xmlns:#{pre}='#{uri}'"}.join(' ')}>
#{block_given? ? yield : content}
</rss>
EORSS
    end

    def make_channel20(content=nil)
      <<-EOC
<channel>
  <title>#{TITLE_VALUE}</title>
  <link>#{LINK_VALUE}</link>
  <description>#{DESCRIPTION_VALUE}</description>
  <language>#{LANGUAGE_VALUE}</language>

  <image>
    <url>#{RDF_RESOURCE}</url>
    <title>#{TITLE_VALUE}</title>
    <link>#{LINK_VALUE}</link>
  </image>

#{RESOURCES.collect do |res| '<item><link>' + res + '</link></item>' end.join("\n")}

  <textInput>
    <title>#{TITLE_VALUE}</title>
    <description>#{DESCRIPTION_VALUE}</description>
    <name>#{NAME_VALUE}</name>
    <link>#{RDF_RESOURCE}</link>
  </textInput>

#{block_given? ? yield : content}
</channel>
EOC
    end

    def make_item20(content=nil)
      <<-EOI
<item>
  <title>#{TITLE_VALUE}</title>
  <link>#{LINK_VALUE}</link>
  <description>#{DESCRIPTION_VALUE}</description>
#{block_given? ? yield : content}
</item>
EOI
    end

    def make_cloud20
      <<-EOC
<cloud
  domain="#{CLOUD_DOMAIN}"
  port="#{CLOUD_PORT}"
  path="#{CLOUD_PATH}"
  registerProcedure="#{CLOUD_REGISTER_PROCEDURE}"
  protocol="#{CLOUD_PROTOCOL}" />
EOC
    end

    private
    def setup_dummy_channel(maker)
      about = "http://hoge.com"
      title = "fugafuga"
      link = "http://hoge.com"
      description = "fugafugafugafuga"
      language = "ja"

      maker.channel.about = about
      maker.channel.title = title
      maker.channel.link = link
      maker.channel.description = description
      maker.channel.language = language
    end

    def setup_dummy_image(maker)
      title = "fugafuga"
      link = "http://hoge.com"
      url = "http://hoge.com/hoge.png"

      maker.channel.link = link if maker.channel.link.nil?
      
      maker.image.title = title
      maker.image.url = url
    end

    def setup_dummy_textinput(maker)
      title = "fugafuga"
      description = "text hoge fuga"
      name = "hoge"
      link = "http://hoge.com/search.cgi"

      maker.textinput.title = title
      maker.textinput.description = description
      maker.textinput.name = name
      maker.textinput.link = link
    end

    def setup_dummy_item(maker)
      title = "TITLE"
      link = "http://hoge.com/"

      item = maker.items.new_item
      item.title = title
      item.link = link
    end
    
  end
end
