require "rexml/text"

module REXML
	class CData < Text
		START = '<![CDATA['
		STOP = ']]>'
		ILLEGAL = /(\]\]>)/

		#	Constructor.  CData is data between <![CDATA[ ... ]]>
		#
		# _Examples_
		#  CData.new( source )
		#  CData.new( "Here is some CDATA" )
		#  CData.new( "Some unprocessed data", respect_whitespace_TF, parent_element )
		def initialize( first, whitespace=true, parent=nil )
			super( first, whitespace, parent, true, true, ILLEGAL )
		end

		# Make a copy of this object
		# 
		# _Examples_
		#  c = CData.new( "Some text" )
		#  d = c.clone
		#  d.to_s        # -> "Some text"
		def clone
			CData.new self
		end

		# Returns the content of this CData object
		#
		# _Examples_
		#  c = CData.new( "Some text" )
		#  c.to_s        # -> "Some text"
		def to_s
			@string
		end

		# Generates XML output of this object
		#
		# output::
		#   Where to write the string.  Defaults to $stdout
		# indent::
		#   An integer.  If -1, no indenting will be used; otherwise, the
		#   indentation will be this number of spaces, and children will be
		#   indented an additional amount.  Defaults to -1.
		# transitive::
		#   If transitive is true and indent is >= 0, then the output will be
		#   pretty-printed in such a way that the added whitespace does not affect
		#   the absolute *value* of the document -- that is, it leaves the value
		#   and number of Text nodes in the document unchanged.
		# ie_hack::
		#   Internet Explorer is the worst piece of crap to have ever been
		#   written, with the possible exception of Windows itself.  Since IE is
		#   unable to parse proper XML, we have to provide a hack to generate XML
		#   that IE's limited abilities can handle.  This hack inserts a space 
		#   before the /> on empty tags.
		#
		# _Examples_
		#  c = CData.new( " Some text " )
		#  c.write( $stdout )     #->  <![CDATA[ Some text ]]>
		def write( output=$stdout, indent=-1, transitive=false, ie_hack=false )
      #indent( output, indent ) unless transitive
			output << START
			output << @string
			output << STOP
		end
	end
end
