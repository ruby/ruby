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

module REXML
  # Represents a full XML document, including PIs, a doctype, etc.  A
  # Document has a single child that can be accessed by root().
  # Note that if you want to have an XML declaration written for a document
  # you create, you must add one; REXML documents do not write a default
	# declaration for you.  See |DECLARATION| and |write|.
	class Document < Element
		# A convenient default XML declaration.  If you want an XML declaration,
		# the easiest way to add one is mydoc << Document::DECLARATION
		DECLARATION = XMLDecl.new( "1.0", "UTF-8" )

		# Constructor
		# @param source if supplied, must be a Document, String, or IO. 
		# Documents have their context and Element attributes cloned.
	  # Strings are expected to be valid XML documents.  IOs are expected
	  # to be sources of valid XML documents.
	  # @param context if supplied, contains the context of the document;
	  # this should be a Hash.
	  # NOTE that I'm not sure what the context is for; I cloned it out of
	  # the Electric XML API (in which it also seems to do nothing), and it
	  # is now legacy.  It may do something, someday... it may disappear.
		def initialize( source = nil, context = {} )
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
				@children.unshift child
			elsif child.kind_of? DocType
				if @children[0].kind_of? XMLDecl
					@children[1,0] = child
				else
					@children.unshift child
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
			@children.find { |item| item.kind_of? Element }
		end

		# @return the DocType child of the document, if one exists,
		# and nil otherwise.
		def doctype
			@children.find { |item| item.kind_of? DocType }
		end

		# @return the XMLDecl of this document; if no XMLDecl has been
		# set, the default declaration is returned.
		def xml_decl
			rv = @children.find { |item| item.kind_of? XMLDecl }
			rv = DECLARATION if rv.nil?
			rv
		end

		# @return the XMLDecl version of this document as a String.
		# If no XMLDecl has been set, returns the default version.
		def version
			decl = xml_decl()
			decl.nil? ? XMLDecl.DEFAULT_VERSION : decl.version
		end

		# @return the XMLDecl encoding of this document as a String.
		# If no XMLDecl has been set, returns the default encoding.
		def encoding
			decl = xml_decl()
			decl.nil? or decl.encoding.nil? ? XMLDecl.DEFAULT_ENCODING : decl.encoding
		end

		# @return the XMLDecl standalone value of this document as a String.
		# If no XMLDecl has been set, returns the default setting.
		def stand_alone?
			decl = xml_decl()
			decl.nil? ? XMLDecl.DEFAULT_STANDALONE : decl.stand_alone?
		end

		# Write the XML tree out, optionally with indent.  This writes out the
		# entire XML document, including XML declarations, doctype declarations,
		# and processing instructions (if any are given).
		# A controversial point is whether Document should always write the XML
		# declaration (<?xml version='1.0'?>) whether or not one is given by the
		# user (or source document).  REXML does not write one if one was not
		# specified, because it adds unneccessary bandwidth to applications such
		# as XML-RPC.
		#
		#
		# output::
		#	  output an object which supports '<< string'; this is where the
		#   document will be written.
		# indent::
		#   An integer.  If -1, no indenting will be used; otherwise, the
		#   indentation will be this number of spaces, and children will be
		#   indented an additional amount.  Defaults to -1
		# transitive::
		#   What the heck does this do? Defaults to false
		# ie_hack::
		#   Internet Explorer is the worst piece of crap to have ever been
		#   written, with the possible exception of Windows itself.  Since IE is
		#   unable to parse proper XML, we have to provide a hack to generate XML
		#   that IE's limited abilities can handle.  This hack inserts a space 
		#   before the /> on empty tags.  Defaults to false
		def write( output=$stdout, indent=-1, transitive=false, ie_hack=false )
			output = Output.new( output, xml_decl.encoding ) if xml_decl.encoding != "UTF-8"
			@children.each { |node|
				node.write( output, indent, transitive, ie_hack )
				output << "\n" unless indent<0 or node == @children[-1]
			}
		end

		
		def Document::parse_stream( source, listener )
			Parsers::StreamParser.new( source, listener ).parse
		end

		private
		def build( source )
			build_context = self
			parser = Parsers::BaseParser.new( source )
			tag_stack = []
			in_doctype = false
			entities = nil
			while true
				event = parser.pull
				case event[0]
				when :end_document
					return
				when :start_element
					tag_stack.push(event[1])
					# find the observers for namespaces
					build_context = build_context.add_element( event[1], event[2] )
				when :end_element
					tag_stack.pop
					build_context = build_context.parent
				when :text
					if not in_doctype
						if build_context[-1].instance_of? Text
							build_context[-1] << event[1]
						else
							build_context.add( 
								Text.new( event[1], true, nil, true ) 
							) unless (
								event[1].strip.size == 0 and 
								build_context.ignore_whitespace_nodes
							)
						end
					end
				when :comment
					c = Comment.new( event[1] )
					build_context.add( c )
				when :cdata
					c = CData.new( event[1] )
					build_context.add( c )
				when :processing_instruction
					build_context.add( Instruction.new( event[1], event[2] ) )
				when :end_doctype
					in_doctype = false
					entities.each { |k,v| entities[k] = build_context.entities[k].value }
					build_context = build_context.parent
				when :start_doctype
					doctype = DocType.new( event[1..-1], build_context )
					build_context = doctype
					entities = {}
					in_doctype = true
				when :attlistdecl
					n = AttlistDecl.new( event[1..-1] )
					build_context.add( n )
				when :elementdecl
					n = ElementDecl.new( event[1] )
					build_context.add(n)
				when :entitydecl
					entities[ event[1] ] = event[2] unless event[2] =~ /PUBLIC|SYSTEM/
					build_context.add(Entity.new(event))
				when :notationdecl
					n = NotationDecl.new( *event[1..-1] )
					build_context.add( n )
				when :xmldecl
					x = XMLDecl.new( event[1], event[2], event[3] )
					build_context.add( x )
				end
			end
		end
	end
end
