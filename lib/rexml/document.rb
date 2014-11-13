require "rexml/security"
require "rexml/element"
require "rexml/xmldecl"
require "rexml/source"
require "rexml/comment"
require "rexml/doctype"
require "rexml/instruction"
require "rexml/rexml"
require "rexml/parseexception"
require "rexml/output"
require "rexml/parsers/baseparser"
require "rexml/parsers/streamparser"
require "rexml/parsers/treeparser"

module REXML
  # Represents a full XML document, including PIs, a doctype, etc.  A
  # Document has a single child that can be accessed by root().
  # Note that if you want to have an XML declaration written for a document
  # you create, you must add one; REXML documents do not write a default
  # declaration for you.  See |DECLARATION| and |write|.
  class Document < Element
    # A convenient default XML declaration.  If you want an XML declaration,
    # the easiest way to add one is mydoc << Document::DECLARATION
    # +DEPRECATED+
    # Use: mydoc << XMLDecl.default
    DECLARATION = XMLDecl.default

    # Constructor
    # @param source if supplied, must be a Document, String, or IO.
    # Documents have their context and Element attributes cloned.
    # Strings are expected to be valid XML documents.  IOs are expected
    # to be sources of valid XML documents.
    # @param context if supplied, contains the context of the document;
    # this should be a Hash.
    def initialize( source = nil, context = {} )
      @entity_expansion_count = 0
      super()
      @context = context
      return if source.nil?
      if source.kind_of? Document
        @context = source.context
        super source
      else
        build(  source )
      end
    end

    def node_type
      :document
    end

    # Should be obvious
    def clone
      Document.new self
    end

    # According to the XML spec, a root node has no expanded name
    def expanded_name
      ''
      #d = doc_type
      #d ? d.name : "UNDEFINED"
    end

    alias :name :expanded_name

    # We override this, because XMLDecls and DocTypes must go at the start
    # of the document
    def add( child )
      if child.kind_of? XMLDecl
        if @children[0].kind_of? XMLDecl
          @children[0] = child
        else
          @children.unshift child
        end
        child.parent = self
      elsif child.kind_of? DocType
        # Find first Element or DocType node and insert the decl right
        # before it.  If there is no such node, just insert the child at the
        # end.  If there is a child and it is an DocType, then replace it.
        insert_before_index = @children.find_index { |x|
          x.kind_of?(Element) || x.kind_of?(DocType)
        }
        if insert_before_index # Not null = not end of list
          if @children[ insert_before_index ].kind_of? DocType
            @children[ insert_before_index ] = child
          else
            @children[ insert_before_index-1, 0 ] = child
          end
        else  # Insert at end of list
          @children << child
        end
        child.parent = self
      else
        rv = super
        raise "attempted adding second root element to document" if @elements.size > 1
        rv
      end
    end
    alias :<< :add

    def add_element(arg=nil, arg2=nil)
      rv = super
      raise "attempted adding second root element to document" if @elements.size > 1
      rv
    end

    # @return the root Element of the document, or nil if this document
    # has no children.
    def root
      elements[1]
      #self
      #@children.find { |item| item.kind_of? Element }
    end

    # @return the DocType child of the document, if one exists,
    # and nil otherwise.
    def doctype
      @children.find { |item| item.kind_of? DocType }
    end

    # @return the XMLDecl of this document; if no XMLDecl has been
    # set, the default declaration is returned.
    def xml_decl
      rv = @children[0]
      return rv if rv.kind_of? XMLDecl
      rv = @children.unshift(XMLDecl.default)[0]
    end

    # @return the XMLDecl version of this document as a String.
    # If no XMLDecl has been set, returns the default version.
    def version
      xml_decl().version
    end

    # @return the XMLDecl encoding of this document as an
    # Encoding object.
    # If no XMLDecl has been set, returns the default encoding.
    def encoding
      xml_decl().encoding
    end

    # @return the XMLDecl standalone value of this document as a String.
    # If no XMLDecl has been set, returns the default setting.
    def stand_alone?
      xml_decl().stand_alone?
    end

    # :call-seq:
    #    doc.write(output=$stdout, indent=-1, transtive=false, ie_hack=false, encoding=nil)
    #    doc.write(options={:output => $stdout, :indent => -1, :transtive => false, :ie_hack => false, :encoding => nil})
    #
    # Write the XML tree out, optionally with indent.  This writes out the
    # entire XML document, including XML declarations, doctype declarations,
    # and processing instructions (if any are given).
    #
    # A controversial point is whether Document should always write the XML
    # declaration (<?xml version='1.0'?>) whether or not one is given by the
    # user (or source document).  REXML does not write one if one was not
    # specified, because it adds unnecessary bandwidth to applications such
    # as XML-RPC.
    #
    # Accept Nth argument style and options Hash style as argument.
    # The recommended style is options Hash style for one or more
    # arguments case.
    #
    # _Examples_
    #   Document.new("<a><b/></a>").write
    #
    #   output = ""
    #   Document.new("<a><b/></a>").write(output)
    #
    #   output = ""
    #   Document.new("<a><b/></a>").write(:output => output, :indent => 2)
    #
    # See also the classes in the rexml/formatters package for the proper way
    # to change the default formatting of XML output.
    #
    # _Examples_
    #
    #   output = ""
    #   tr = Transitive.new
    #   tr.write(Document.new("<a><b/></a>"), output)
    #
    # output::
    #   output an object which supports '<< string'; this is where the
    #   document will be written.
    # indent::
    #   An integer.  If -1, no indenting will be used; otherwise, the
    #   indentation will be twice this number of spaces, and children will be
    #   indented an additional amount.  For a value of 3, every item will be
    #   indented 3 more levels, or 6 more spaces (2 * 3). Defaults to -1
    # transitive::
    #   If transitive is true and indent is >= 0, then the output will be
    #   pretty-printed in such a way that the added whitespace does not affect
    #   the absolute *value* of the document -- that is, it leaves the value
    #   and number of Text nodes in the document unchanged.
    # ie_hack::
    #   This hack inserts a space before the /> on empty tags to address
    #   a limitation of Internet Explorer.  Defaults to false
    # encoding::
    #   Encoding name as String. Change output encoding to specified encoding
    #   instead of encoding in XML declaration.
    #   Defaults to nil. It means encoding in XML declaration is used.
    def write(*arguments)
      if arguments.size == 1 and arguments[0].class == Hash
        options = arguments[0]

        output     = options[:output]
        indent     = options[:indent]
        transitive = options[:transitive]
        ie_hack    = options[:ie_hack]
        encoding   = options[:encoding]
      else
        output, indent, transitive, ie_hack, encoding, = *arguments
      end

      output   ||= $stdout
      indent   ||= -1
      transitive = false if transitive.nil?
      ie_hack    = false if ie_hack.nil?
      encoding ||= xml_decl.encoding

      if encoding != 'UTF-8' && !output.kind_of?(Output)
        output = Output.new( output, encoding )
      end
      formatter = if indent > -1
          if transitive
            require "rexml/formatters/transitive"
            REXML::Formatters::Transitive.new( indent, ie_hack )
          else
            REXML::Formatters::Pretty.new( indent, ie_hack )
          end
        else
          REXML::Formatters::Default.new( ie_hack )
        end
      formatter.write( self, output )
    end


    def Document::parse_stream( source, listener )
      Parsers::StreamParser.new( source, listener ).parse
    end

    # Set the entity expansion limit. By default the limit is set to 10000.
    #
    # Deprecated. Use REXML::Security.entity_expansion_limit= instead.
    def Document::entity_expansion_limit=( val )
      Security.entity_expansion_limit = val
    end

    # Get the entity expansion limit. By default the limit is set to 10000.
    #
    # Deprecated. Use REXML::Security.entity_expansion_limit= instead.
    def Document::entity_expansion_limit
      return Security.entity_expansion_limit
    end

    # Set the entity expansion limit. By default the limit is set to 10240.
    #
    # Deprecated. Use REXML::Security.entity_expansion_text_limit= instead.
    def Document::entity_expansion_text_limit=( val )
      Security.entity_expansion_text_limit = val
    end

    # Get the entity expansion limit. By default the limit is set to 10240.
    #
    # Deprecated. Use REXML::Security.entity_expansion_text_limit instead.
    def Document::entity_expansion_text_limit
      return Security.entity_expansion_text_limit
    end

    attr_reader :entity_expansion_count

    def record_entity_expansion
      @entity_expansion_count += 1
      if @entity_expansion_count > Security.entity_expansion_limit
        raise "number of entity expansions exceeded, processing aborted."
      end
    end

    def document
      self
    end

    private
    def build( source )
      Parsers::TreeParser.new( source, self ).parse
    end
  end
end
