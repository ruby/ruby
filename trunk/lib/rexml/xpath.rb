require 'rexml/functions'
require 'rexml/xpath_parser'

module REXML
	# Wrapper class.  Use this class to access the XPath functions.
	class XPath
		include Functions
		EMPTY_HASH = {}

		# Finds and returns the first node that matches the supplied xpath.
		# element::
		# 	The context element
		# path::
		# 	The xpath to search for.  If not supplied or nil, returns the first
		# 	node matching '*'.
		# namespaces::
		# 	If supplied, a Hash which defines a namespace mapping.
		#
		#  XPath.first( node )
		#  XPath.first( doc, "//b"} )
		#  XPath.first( node, "a/x:b", { "x"=>"http://doofus" } )
    def XPath::first element, path=nil, namespaces=nil, variables={}
      raise "The namespaces argument, if supplied, must be a hash object." unless namespaces.nil? or namespaces.kind_of?(Hash)
      raise "The variables argument, if supplied, must be a hash object." unless variables.kind_of?(Hash)
			parser = XPathParser.new
			parser.namespaces = namespaces
			parser.variables = variables
			path = "*" unless path
			element = [element] unless element.kind_of? Array
			parser.parse(path, element).flatten[0]
		end

		# Iterates over nodes that match the given path, calling the supplied
		# block with the match.
		# element::
		#   The context element
		# path::
		#   The xpath to search for.  If not supplied or nil, defaults to '*'
		# namespaces::
		# 	If supplied, a Hash which defines a namespace mapping
		#
		#  XPath.each( node ) { |el| ... }
		#  XPath.each( node, '/*[@attr='v']' ) { |el| ... }
		#  XPath.each( node, 'ancestor::x' ) { |el| ... }
		def XPath::each element, path=nil, namespaces=nil, variables={}, &block
      raise "The namespaces argument, if supplied, must be a hash object." unless namespaces.nil? or namespaces.kind_of?(Hash)
      raise "The variables argument, if supplied, must be a hash object." unless variables.kind_of?(Hash)
			parser = XPathParser.new
			parser.namespaces = namespaces
			parser.variables = variables
			path = "*" unless path
			element = [element] unless element.kind_of? Array
			parser.parse(path, element).each( &block )
		end

		# Returns an array of nodes matching a given XPath.  
		def XPath::match element, path=nil, namespaces=nil, variables={}
			parser = XPathParser.new
			parser.namespaces = namespaces
			parser.variables = variables
			path = "*" unless path
			element = [element] unless element.kind_of? Array
			parser.parse(path,element)
		end
	end
end
