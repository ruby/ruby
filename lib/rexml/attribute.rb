require "rexml/namespace"
require 'rexml/text'

module REXML
	# Defines an Element Attribute; IE, a attribute=value pair, as in:
	# <element attribute="value"/>.  Attributes can be in their own
	# namespaces.  General users of REXML will not interact with the
	# Attribute class much.
	class Attribute
		include Node
		include Namespace

		# The element to which this attribute belongs
		attr_reader :element
		# The normalized value of this attribute.  That is, the attribute with
		# entities intact.
		attr_writer :normalized	
		PATTERN = /\s*(#{NAME_STR})\s*=\s*(["'])(.*?)\2/um

		# Constructor.
		#
		#  Attribute.new( attribute_to_clone )
		#  Attribute.new( source )
		#  Attribute.new( "attr", "attr_value" )
		#  Attribute.new( "attr", "attr_value", parent_element )
		def initialize( first, second=nil, parent=nil )
			@normalized = @unnormalized = @element = nil
			if first.kind_of? Attribute
				self.name = first.expanded_name
				@value = first.value
				if second.kind_of? Element
					@element = second
				else
					@element = first.element
				end
			elsif first.kind_of? String
				@element = parent if parent.kind_of? Element
				self.name = first
				@value = second.to_s
			else
				raise "illegal argument #{first.class.name} to Attribute constructor"
			end
		end

		# Returns the namespace of the attribute.
		# 
		#  e = Element.new( "elns:myelement" )
		#  e.add_attribute( "nsa:a", "aval" )
		#  e.add_attribute( "b", "bval" )
		#  e.attributes.get_attribute( "a" ).prefix   # -> "nsa"
		#  e.attributes.get_attribute( "b" ).prefix   # -> "elns"
		#  a = Attribute.new( "x", "y" )
		#  a.prefix                                   # -> ""
		def prefix
			pf = super
			if pf == ""
				pf = @element.prefix if @element
			end
			pf
		end

		# Returns the namespace URL, if defined, or nil otherwise
		# 
		#  e = Element.new("el")
		#  e.add_attributes({"xmlns:ns", "http://url"})
		#  e.namespace( "ns" )              # -> "http://url"
		def namespace arg=nil
			arg = prefix if arg.nil?
			@element.namespace arg
		end

		# Returns true if other is an Attribute and has the same name and value,
		# false otherwise.
		def ==( other )
			other.kind_of?(Attribute) and other.name==name and other.value==@value
		end

		# Creates (and returns) a hash from both the name and value
		def hash
			name.hash + value.hash
		end

		# Returns this attribute out as XML source, expanding the name
		#
		#  a = Attribute.new( "x", "y" )
		#  a.to_string     # -> "x='y'"
		#  b = Attribute.new( "ns:x", "y" )
		#  b.to_string     # -> "ns:x='y'"
		def to_string
			"#@expanded_name='#{to_s().gsub(/'/, '&apos;')}'"
		end

		# Returns the attribute value, with entities replaced
		def to_s
			return @normalized if @normalized

			doctype = nil
			if @element
				doc = @element.document
				doctype = doc.doctype if doc
			end

			@unnormalized = nil
			@value = @normalized = Text::normalize( @value, doctype )
		end

		# Returns the UNNORMALIZED value of this attribute.  That is, entities
		# have been expanded to their values
		def value
			@unnormalized if @unnormalized
			doctype = nil
			if @element
				doc = @element.document
				doctype = doc.doctype if doc
			end
			@normalized = nil
			@value = @unnormalized = Text::unnormalize( @value, doctype )
		end

		# Returns a copy of this attribute
		def clone
			Attribute.new self
		end

		# Sets the element of which this object is an attribute.  Normally, this
		# is not directly called.
		#
		# Returns this attribute
		def element=( element )
			@element = element
			self
		end

		# Removes this Attribute from the tree, and returns true if successfull
		# 
		# This method is usually not called directly.
		def remove
			@element.attributes.delete self.name unless @element.nil?
		end

		# Writes this attribute (EG, puts 'key="value"' to the output)
		def write( output, indent=-1 )
			output << to_string
		end

    def node_type
      :attribute
    end

    def inspect
      rv = ""
      write( rv )
      rv
    end

    def xpath
      path = @element.xpath
      path += "/@#{self.expanded_name}"
      return path
    end
	end
end
#vim:ts=2 sw=2 noexpandtab:
