require 'rexml/xmltokens'
require 'rexml/light/node'

# Development model
# document = Node.new

# Add an element "foo" to the document
# foo = document << "foo"
# # Set attribute "attr" on foo
# foo["attr"] = "la"
# # Set another attribute in a different namespace
# foo["attr", "namespace"] = "too"
# # Swap foo into another namespace
# foo.namespace = "blah"
# # Add a couple of element nodes to foo
# foo << "a"
# foo << "b"
# # Access the children of foo in various ways
# a = foo[0]
# foo.each { |child|
#         #...
# }
# # Add text to foo
# # Add instruction
# # Add comment
# # Get the root of the document
# document == a.root
# # Write the document out
# puts document.to_s
module REXML
	module Light
		# Represents a tagged XML element.  Elements are characterized by
		# having children, attributes, and names, and can themselves be
		# children.
		class Node < Array
			alias :_old_get :[]
			alias :_old_put :[]=

			NAMESPLIT = /^(?:(#{XMLTokens::NCNAME_STR}):)?(#{XMLTokens::NCNAME_STR})/u
			# Create a new element.
			def initialize node=nil
				if node.kind_of? String
					node = [ :text, node ]
				elsif node.nil?
					node = [ :document, nil, nil ]
				elsif node[0] == :start_element
					node[0] = :element
				end
				replace( node )
				_old_put( 1, 0, 1 )
				_old_put( 1, nil )
			end

			def size
				el!()
				super-4
			end

			def each( &block )
				el!()
				size.times { |x| yield( at(x+4) ) }
			end

			def name
				el!()
				at(2)
			end

			def name=( name_str, ns=nil )
				el!()
				pfx = ''
				pfx = "#{prefix(ns)}:" if ns
				_old_put(1, "#{pfx}#{name_str}")
			end

			def parent=( node )
				_old_put(1,node)
			end

			def local_name
				el!()
				namesplit
				@name
			end

			def local_name=( name_str )
				el!()
				_old_put( 1, "#@prefix:#{name_str}" )
			end

			def prefix( namespace=nil )
				el!()
				prefix_of( self, namespace )
			end

			def namespace( prefix=prefix() )
				el!()
				namespace_of( self, prefix )
			end

			def namespace=( namespace )
				el!()
				@prefix = prefix( namespace )
				pfx = ''
				pfx = "#@prefix:" if @prefix.size > 0
				_old_put(1, "#{pfx}#@name")
			end

			def []( reference, ns=nil )
				el!()
				if reference.kind_of? String
					pfx = ''
					pfx = "#{prefix(ns)}:" if ns
					at(3)["#{pfx}#{reference}"]
				elsif reference.kind_of? Range
					_old_get( Range.new(4+reference.begin, reference.end, reference.exclude_end?) )
				else
					_old_get( 4+reference )
				end
			end

			def =~( path )
				XPath.match( self, path )
			end

			# Doesn't handle namespaces yet
			def []=( reference, ns, value=nil )
				el!()
				if reference.kind_of? String
					value = ns unless value
					at( 3 )[reference] = value
				elsif reference.kind_of? Range
					_old_put( Range.new(3+reference.begin, reference.end, reference.exclude_end?), ns )
				else
					if value
						_old_put( 4+reference, ns, value )
					else
						_old_put( 4+reference, ns )
					end
				end
			end

			# Append a child to this element, optionally under a provided namespace.
			# The namespace argument is ignored if the element argument is an Element
			# object.  Otherwise, the element argument is a string, the namespace (if
			# provided) is the namespace the element is created in.
			def << element
				if node_type() == :text
					at(-1) << element
				else
					newnode = Node.new( element )
					newnode.parent = self
					self.push( newnode )
				end
				at(-1)
			end

			def node_type
				_old_get(0)
			end

			def text=( foo )
				replace = at(4).kind_of? String ? 1 : 0
				self._old_put(4,replace, normalizefoo)
			end

			def root
				context = self
				context = context.at(1) while context.at(1)
			end

			def has_name?( name, namespace = '' )
				el!()
				at(3) == name and namespace() == namespace
			end

			def children
				el!()
				self
			end

			def parent
				at(1)
			end

			def to_s

			end

			def el!
				if node_type() != :element and node_type() != :document
					_old_put( 0, :element )
					push({})
				end
				self
			end

			private

			def namesplit
				return if @name.defined?
				at(2) =~ NAMESPLIT
				@prefix = '' || $1
				@name = $2
			end

			def namespace_of( node, prefix=nil )
				if not prefix
					name = at(2)
					name =~ NAMESPLIT
					prefix = $1
				end
				to_find = 'xmlns'
				to_find = "xmlns:#{prefix}" if not prefix.nil?
				ns = at(3)[ to_find ]
				ns ? ns : namespace_of( @node[0], prefix )
			end

			def prefix_of( node, namespace=nil )
				if not namespace
					name = node.name
					name =~ NAMESPLIT
					$1
				else
					ns = at(3).find { |k,v| v == namespace }
					ns ? ns : prefix_of( node.parent, namespace )
				end
			end
		end
	end
end
