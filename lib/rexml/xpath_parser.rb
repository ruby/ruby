require 'rexml/namespace'
require 'rexml/xmltokens'
require 'rexml/parsers/xpathparser'

# Ignore this class.  It adds a __ne__ method, because Ruby doesn't seem to
# understand object.send( "!=", foo ), whereas it *does* understand "<", "==",
# and all of the other comparison methods.  Stupid, and annoying, and not at
# all POLS.
class Object
	def __ne__(b)
		self != b
	end
end

module REXML
	# You don't want to use this class.  Really.  Use XPath, which is a wrapper
	# for this class.  Believe me.  You don't want to poke around in here.
	# There is strange, dark magic at work in this code.  Beware.  Go back!  Go
	# back while you still can!
	class XPathParser
		include XMLTokens
		LITERAL		= /^'([^']*)'|^"([^"]*)"/u

		def initialize( )
			@parser = REXML::Parsers::XPathParser.new
			@namespaces = {}
			@variables = {}
		end

		def namespaces=( namespaces={} )
			Functions::namespace_context = namespaces
			@namespaces = namespaces
		end

		def variables=( vars={} )
			Functions::variables = vars
			@variables = vars
		end

		def parse path, nodeset
			path_stack = @parser.parse( path )
			#puts "PARSE: #{path} => #{path_stack.inspect}"
			match( path_stack, nodeset )
		end

		def predicate path, nodeset
			path_stack = @parser.predicate( path )
			return Predicate( path_stack, nodeset )
		end

		def []=( variable_name, value )
			@variables[ variable_name ] = value
		end

		private

		def match( path_stack, nodeset ) 
			while ( path_stack.size > 0 and nodeset.size > 0 ) 
				#puts "PARSE: #{path_stack.inspect} '#{nodeset.collect{|n|n.type}.inspect}'"
				nodeset = internal_parse( path_stack, nodeset )
				#puts "NODESET: #{nodeset.size}"
				#puts "PATH_STACK: #{path_stack.inspect}"
			end
			nodeset
		end

		def internal_parse path_stack, nodeset
			return nodeset if nodeset.size == 0 or path_stack.size == 0
			#puts "INTERNAL_PARSE: #{path_stack.inspect}, #{nodeset.collect{|n| n.type}.inspect}"
			case path_stack.shift
			when :document
				return [ nodeset[0].root.parent ]

			when :qname
				prefix = path_stack.shift
				name = path_stack.shift
				#puts "QNAME #{prefix}#{prefix.size>0?':':''}#{name}"
				n = nodeset.clone
				ns = @namespaces[prefix]
				ns = ns ? ns : ''
				n.delete_if do |node|
					# FIXME: This DOUBLES the time XPath searches take
					ns = node.namespace( prefix ) if node.node_type == :element and ns == ''
					#puts "NODE: '#{node.to_s}'; node.has_name?( #{name.inspect}, #{ns.inspect} ): #{ node.has_name?( name, ns )}; node.namespace() = #{node.namespace().inspect}; node.prefix = #{node.prefix().inspect}" if node.node_type == :element
					!(node.node_type == :element and node.name == name and node.namespace == ns )
				end
				return n

			when :any
				n = nodeset.clone
				n.delete_if { |node| node.node_type != :element }
				return n

			when :self
				# THIS SPACE LEFT INTENTIONALLY BLANK

			when :processing_instruction
				target = path_stack.shift
				n = nodeset.clone
				n.delete_if do |node|
					(node.node_type != :processing_instruction) or 
					( !target.nil? and ( node.target != target ) )
				end
				return n

			when :text
				#puts ":TEXT"
				n = nodeset.clone
				n.delete_if do |node|
					#puts "#{node} :: #{node.node_type}"
					node.node_type != :text
				end
				return n

			when :comment
				n = nodeset.clone
				n.delete_if do |node|
					node.node_type != :comment
				end
				return n

			when :node
				return nodeset
				#n = nodeset.clone
				#n.delete_if do |node|
				#	!node.node?
				#end
				#return n
			
			# FIXME:  I suspect the following XPath will fail:
			# /a/*/*[1]
			when :child
				#puts "CHILD"
				new_nodeset = []
				ps_clone = nil
				for node in nodeset
					#ps_clone = path_stack.clone
					#new_nodeset += internal_parse( ps_clone, node.children ) if node.parent?
					new_nodeset += node.children if node.parent?
				end
				#path_stack[0,(path_stack.size-ps_clone.size)] = []
				return new_nodeset

			when :literal
				literal = path_stack.shift
				if literal =~ /^\d+(\.\d+)?$/
					return ($1 ? literal.to_f : literal.to_i) 
				end
				#puts "RETURNING '#{literal}'"
				return literal
				
			when :attribute
				#puts ":ATTRIBUTE"
				new_nodeset = []
				case path_stack.shift
				when :qname
					prefix = path_stack.shift
					name = path_stack.shift
					for element in nodeset
						if element.node_type == :element
							#puts element.name
							#puts "looking for attribute #{name} in '#{@namespaces[prefix]}'"
							attr = element.attribute( name, @namespaces[prefix] )
							#puts ":ATTRIBUTE: attr => #{attr}"
							new_nodeset << attr if attr
						end
					end
				when :any
					for element in nodeset
						if element.node_type == :element
							attr = element.attributes
						end
					end
				end
				#puts "RETURNING #{new_nodeset.collect{|n|n.to_s}.inspect}"
				return new_nodeset

			when :parent
				return internal_parse( path_stack, nodeset.collect{|n| n.parent}.compact )

			when :ancestor
				#puts "ANCESTOR"
				new_nodeset = []
				for node in nodeset
					while node.parent
						node = node.parent
						new_nodeset << node unless new_nodeset.include? node
					end
				end
				#nodeset = new_nodeset.uniq
				return new_nodeset

			when :ancestor_or_self
				new_nodeset = []
				for node in nodeset
					if node.node_type == :element
						new_nodeset << node
						while ( node.parent )
							node = node.parent
							new_nodeset << node unless new_nodeset.includes? node
						end
					end
				end
				#nodeset = new_nodeset.uniq
				return new_nodeset

			when :predicate
				#puts "@"*80
				#puts "NODESET = #{nodeset.collect{|n|n.to_s}.inspect}"
				predicate = path_stack.shift
				new_nodeset = []
				Functions::size = nodeset.size
				nodeset.size.times do |index|
					node = nodeset[index]
					Functions::node = node
					Functions::index = index+1
					#puts "Node #{node} and index=#{index+1}"
					result = Predicate( predicate, node )
					#puts "Predicate returned #{result} (#{result.type}) for #{node.type}"
					if result.kind_of? Numeric
						#puts "#{result} == #{index} => #{result == index}"
						new_nodeset << node if result == (index+1)
					elsif result.instance_of? Array
						new_nodeset << node if result.size > 0
					else
						new_nodeset << node if result
					end
				end
				#puts "Nodeset after predicate #{predicate.inspect} has #{new_nodeset.size} nodes"
				#puts "NODESET: #{new_nodeset.collect{|n|n.to_s}.inspect}"
				return new_nodeset

			when :descendant_or_self
				rv = descendant_or_self( path_stack, nodeset )
				path_stack.clear
				return rv

			when :descendant
				#puts ":DESCENDANT"
				results = []
				for node in nodeset
					results += internal_parse( path_stack.clone.unshift( :descendant_or_self ),
						node.children ) if node.parent?
				end
				return results

			when :following_sibling
				results = []
				for node in nodeset
					all_siblings = node.parent.children
					current_index = all_siblings.index( node )
					following_siblings = all_siblings[ current_index+1 .. -1 ]
					results += internal_parse( path_stack.clone, following_siblings )
				end
				return results

			when :preceding_sibling
				results = []
				for node in nodeset
					all_siblings = node.parent.children
					current_index = all_siblings.index( node )
					preceding_siblings = all_siblings[ 0 .. current_index-1 ]
					results += internal_parse( path_stack.clone, preceding_siblings )
				end
				return results

			when :preceding
				new_nodeset = []
				for node in nodeset
					new_nodeset += preceding( node )
				end
				return new_nodeset

			when :following
				new_nodeset = []
				for node in nodeset
					new_nodeset += following( node )
				end
				return new_nodeset

			when :namespace
				new_set = []
				for node in nodeset
					new_nodeset << node.namespace if node.node_type == :element or node.node_type == :attribute
				end
				return new_nodeset

			when :variable
				var_name = path_stack.shift
				return @variables[ var_name ]

			end
			nodeset
		end

		##########################################################
		# The next two methods are BAD MOJO!
		# This is my achilles heel.  If anybody thinks of a better
		# way of doing this, be my guest.  This really sucks, but 
		# it took me three days to get it to work at all.
		# ########################################################
		
		def descendant_or_self( path_stack, nodeset )
			rs = []
			d_o_s( path_stack, nodeset, rs )
			#puts "RS = #{rs.collect{|n|n.to_s}.inspect}"
			rs.flatten.compact
		end

		def d_o_s( p, ns, r )
			#puts r.collect{|n|n.to_s}.inspect
			#puts ns.collect{|n|n.to_s}.inspect
			ns.each_index do |i|
				n = ns[i]
				x = match( p.clone, [ n ] )
				#puts "Got a match on #{p.inspect} for #{ns.collect{|n|n.to_s+"("+n.type.to_s+")"}.inspect}"
				d_o_s( p, n.children, x ) if n.parent?
				r[i,0] = [x] if x.size > 0
			end
		end

    def recurse( nodeset, &block )
      for node in nodeset
	      yield node
        recurse( node, &block ) if node.node_type == :element
      end
    end


		# Given a predicate, a node, and a context, evaluates to true or false.
		def Predicate( predicate, node )
			predicate = predicate.clone
			#puts "#"*20
			#puts "Predicate( #{predicate.inspect}, #{node.type} )"
			results = []
			case (predicate[0])
			when :and, :or, :eq, :neq, :lt, :lteq, :gt, :gteq
				eq = predicate.shift
				left = Predicate( predicate.shift, node )
				right = Predicate( predicate.shift, node )
				return equality_relational_compare( left, eq, right )

			when :div, :mod, :mult, :plus, :minus, :union
				op = predicate.shift
				left = Predicate( predicate.shift, node )
				right = Predicate( predicate.shift, node )
				left = Functions::number( left )
				right = Functions::number( right )
				case op
				when :div
					return left.to_f / right.to_f
				when :mod
					return left % right
				when :mult
					return left * right
				when :plus
					return left + right
				when :minus
					return left - right
				when :union
					return (left | right)
				end

			when :neg
				predicate.shift
				operand = Functions::number(Predicate( predicate, node ))
				return -operand

			when :not
				predicate.shift
				return !Predicate( predicate.shift, node )

			when :function
				predicate.shift
				func_name = predicate.shift.tr('-', '_')
				arguments = predicate.shift
				#puts "\nFUNCTION: #{func_name}"
				#puts "ARGUMENTS: #{arguments.inspect} #{node.to_s}"
				args = arguments.collect { |arg| Predicate( arg, node ) }
				#puts "FUNCTION: #{func_name}( #{args.collect{|n|n.to_s}.inspect} )"
				result = Functions.send( func_name, *args )
				#puts "RESULTS: #{result.inspect}"
				return result

			else
				return match( predicate, [ node ] )

			end
		end

		# Builds a nodeset of all of the following nodes of the supplied node,
		# in document order
		def following( node )
			all_siblings = node.parent.children
			current_index = all_siblings.index( node )
			following_siblings = all_siblings[ current_index+1 .. -1 ]
			following = []
			recurse( following_siblings ) { |node| following << node }
			following.shift
			#puts "following is returning #{puta following}"
			following
		end

		# Builds a nodeset of all of the preceding nodes of the supplied node,
		# in reverse document order
		def preceding( node )
			all_siblings = node.parent.children
			current_index = all_siblings.index( node )
			preceding_siblings = all_siblings[ 0 .. current_index-1 ]

			preceding_siblings.reverse!
			preceding = []
			recurse( preceding_siblings ) { |node| preceding << node }
			preceding.reverse
		end

		def equality_relational_compare( set1, op, set2 )
			#puts "EQ_REL_COMP: #{set1.to_s}, #{op}, #{set2.to_s}"
			if set1.kind_of? Array and set2.kind_of? Array
				if set1.size == 1 and set2.size == 1
					set1 = set1[0]
					set2 = set2[0]
				else
					set1.each do |i1| 
						i1 = i1.to_s
						set2.each do |i2| 
							i2 = i2.to_s
							return true if compare( i1, op, i2 )
						end
					end
					return false
				end
			end
			#puts "COMPARING VALUES"
			# If one is nodeset and other is number, compare number to each item
			# in nodeset s.t. number op number(string(item))
			# If one is nodeset and other is string, compare string to each item
			# in nodeset s.t. string op string(item)
			# If one is nodeset and other is boolean, compare boolean to each item
			# in nodeset s.t. boolean op boolean(item)
			if set1.kind_of? Array or set2.kind_of? Array
				#puts "ISA ARRAY"
				if set1.kind_of? Array
					a = set1
					b = set2.to_s
				else
					a = set2
					b = set1.to_s
				end

				case b
				when 'true', 'false'
					b = Functions::boolean( b )
					for v in a
						v = Functions::boolean(v)
						return true if compare( v, op, b )
					end
				when /^\d+(\.\d+)?$/
					b = Functions::number( b )
					for v in a
						v = Functions::number(v)
						return true if compare( v, op, b )
					end
				else
					b = Functions::string( b )
					for v in a
						v = Functions::string(v)
						return true if compare( v, op, b )
					end
				end
			else
				# If neither is nodeset,
				#   If op is = or !=
				#     If either boolean, convert to boolean
				#     If either number, convert to number
				#     Else, convert to string
				#   Else
				#     Convert both to numbers and compare
				s1 = set1.to_s
				s2 = set2.to_s
				#puts "EQ_REL_COMP: #{set1}=>#{s1}, #{set2}=>#{s2}"
				if s1 == 'true' or s1 == 'false' or s2 == 'true' or s2 == 'false'
					#puts "Functions::boolean(#{set1})=>#{Functions::boolean(set1)}"
					#puts "Functions::boolean(#{set2})=>#{Functions::boolean(set2)}"
					set1 = Functions::boolean( set1 )
					set2 = Functions::boolean( set2 )
				else
					if op == :eq or op == :neq
						if s1 =~ /^\d+(\.\d+)?$/ or s2 =~ /^\d+(\.\d+)?$/
							set1 = Functions::number( s1 )
							set2 = Functions::number( s2 )
						else
							set1 = Functions::string( set1 )
							set2 = Functions::string( set2 )
						end
					else
						set1 = Functions::number( set1 )
						set2 = Functions::number( set2 )
					end
				end
				#puts "EQ_REL_COMP: #{set1} #{op} #{set2}"
				return compare( set1, op, set2 )
			end
			return false
		end

		def compare a, op, b
			case op
			when :eq
				a == b
			when :neq
				a != b
			when :lt
				a < b
			when :lteq
				a <= b
			when :gt
				a > b
			when :gteq
				a >= b
			when :and
				a and b
			when :or
				a or b
			else
				false
			end
		end
	end
end
