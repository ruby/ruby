require "rexml/child"

module REXML
	##
	# Represents an XML comment; that is, text between <!-- ... -->
	class Comment < Child
		include Comparable
		START = "<!--"
		STOP = "-->"

		attr_accessor :string			# The content text

		##
		# Constructor.  The first argument can be one of three types:
		# @param first If String, the contents of this comment are set to the 
		# argument.  If Comment, the argument is duplicated.  If
		# Source, the argument is scanned for a comment.
		# @param second If the first argument is a Source, this argument 
		# should be nil, not supplied, or a Parent to be set as the parent 
		# of this object
		def initialize( first, second = nil )
			#puts "IN COMMENT CONSTRUCTOR; SECOND IS #{second.type}"
			super(second)
			if first.kind_of? String
				@string = first
			elsif first.kind_of? Comment
				@string = first.string
			end
		end

		def clone
			Comment.new self
		end

		# output::
		#   Where to write the string
		# indent::
		#   An integer.  If -1, no indenting will be used; otherwise, the
		#   indentation will be this number of spaces, and children will be
		#   indented an additional amount.
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
		def write( output, indent=-1, transitive=false, ie_hack=false )
			indent( output, indent )
			output << START
			output << @string
      if indent>-1
        output << "\n"
        indent( output, indent )
      end
			output << STOP
		end

		alias :to_s :string

		##
		# Compares this Comment to another; the contents of the comment are used
		# in the comparison.
		def <=>(other)
			other.to_s <=> @string
		end

		##
		# Compares this Comment to another; the contents of the comment are used
		# in the comparison.
		def ==( other )
			other.kind_of? Comment and
			(other <=> self) == 0
		end

    def node_type
      :comment
    end
	end
end
#vim:ts=2 sw=2 noexpandtab:
