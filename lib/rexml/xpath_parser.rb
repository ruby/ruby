require 'rexml/namespace'
require 'rexml/xmltokens'
require 'rexml/parsers/xpathparser'

module REXML
  # You don't want to use this class.  Really.  Use XPath, which is a wrapper
  # for this class.  Believe me.  You don't want to poke around in here.
  # There is strange, dark magic at work in this code.  Beware.  Go back!  Go
  # back while you still can!
  class XPathParser
    include XMLTokens
    LITERAL    = /^'([^']*)'|^"([^"]*)"/u

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
      #puts "PARSE: nodeset = #{nodeset.collect{|x|x.to_s}.inspect}"
      match( path_stack, nodeset )
    end

    def predicate path, nodeset
      path_stack = @parser.predicate( path )
      return Predicate( path_stack, nodeset )
    end

    def []=( variable_name, value )
      @variables[ variable_name ] = value
    end

    def match( path_stack, nodeset ) 
      while ( path_stack.size > 0 and nodeset.size > 0 ) 
        #puts "PARSE: #{path_stack.inspect} '#{nodeset.collect{|n|n.class}.inspect}'"
        nodeset = internal_parse( path_stack, nodeset )
        #puts "NODESET: #{nodeset}"
        #puts "PATH_STACK: #{path_stack.inspect}"
      end
      nodeset
    end

    private

    def internal_parse path_stack, nodeset
      #puts "INTERNAL_PARSE RETURNING WITH NO RESULTS" if nodeset.size == 0 or path_stack.size == 0
      return nodeset if nodeset.size == 0 or path_stack.size == 0
      #puts "INTERNAL_PARSE: #{path_stack.inspect}, #{nodeset.collect{|n| n.class}.inspect}"
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
      
      # FIXME:  I suspect the following XPath will fail:
      # /a/*/*[1]
      when :child
        #puts "CHILD"
        new_nodeset = []
        nt = nil
        for node in nodeset
          nt = node.node_type
          new_nodeset += node.children if nt == :element or nt == :document
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
					#puts "ANY"
          for element in nodeset
            if element.node_type == :element
              new_nodeset += element.attributes.to_a
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
              new_nodeset << node unless new_nodeset.include? node
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
          #puts "Predicate returned #{result} (#{result.class}) for #{node.class}"
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
        nt = nil
        for node in nodeset
          nt = node.node_type
          results += internal_parse( path_stack.clone.unshift( :descendant_or_self ),
            node.children ) if nt == :element or nt == :document
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
    # FIXME
    # The next two methods are BAD MOJO!
    # This is my achilles heel.  If anybody thinks of a better
    # way of doing this, be my guest.  This really sucks, but 
    # it took me three days to get it to work at all.
    # ########################################################
    
    def descendant_or_self( path_stack, nodeset )
      rs = []
      d_o_s( path_stack, nodeset, rs )
      #puts "RS = #{rs.collect{|n|n.to_s}.inspect}"
      document_order(rs.flatten.compact)
    end

    def d_o_s( p, ns, r )
      nt = nil
      ns.each_index do |i|
        n = ns[i]
        x = match( p.clone, [ n ] )
        nt = n.node_type
        d_o_s( p, n.children, x ) if nt == :element or nt == :document and n.children.size > 0
        r.concat(x) if x.size > 0
      end
    end


    # Reorders an array of nodes so that they are in document order
    # It tries to do this efficiently.
    def document_order( array_of_nodes )
      new_arry = []
      array_of_nodes.each { |node|
        node_idx = [] 
        np = node.node_type == :attribute ? node.element : node
        while np.parent and np.parent.node_type == :element
          node_idx << np.parent.index( np )
          np = np.parent
        end
        new_arry << [ node_idx.reverse.join, node ]
      }
      new_arry.sort{ |s1, s2| s1[0] <=> s2[0] }.collect{ |s| s[1] }
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
      #puts "Predicate( #{predicate.inspect}, #{node.class} )"
      results = []
      case (predicate[0])
      when :and, :or, :eq, :neq, :lt, :lteq, :gt, :gteq
        eq = predicate.shift
        left = Predicate( predicate.shift, node )
        right = Predicate( predicate.shift, node )
        #puts "LEFT = #{left.inspect}"
        #puts "RIGHT = #{right.inspect}"
        return equality_relational_compare( left, eq, right )

      when :div, :mod, :mult, :plus, :minus
        op = predicate.shift
        left = Predicate( predicate.shift, node )
        right = Predicate( predicate.shift, node )
        #puts "LEFT = #{left.inspect}"
        #puts "RIGHT = #{right.inspect}"
        left = Functions::number( left )
        right = Functions::number( right )
        #puts "LEFT = #{left.inspect}"
        #puts "RIGHT = #{right.inspect}"
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
        end

      when :union
        predicate.shift
        left = Predicate( predicate.shift, node )
        right = Predicate( predicate.shift, node )
        return (left | right)

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

      preceding = []
      recurse( preceding_siblings ) { |node| preceding.unshift( node ) }
      preceding
    end

    def equality_relational_compare( set1, op, set2 )
			#puts "#"*80
      if set1.kind_of? Array and set2.kind_of? Array
				#puts "#{set1.size} & #{set2.size}"
        if set1.size == 1 and set2.size == 1
          set1 = set1[0]
          set2 = set2[0]
        elsif set1.size == 0 or set2.size == 0
          nd = set1.size==0 ? set2 : set1
          nd.each { |il| return true if compare( il, op, nil ) }
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
			#puts "EQ_REL_COMP: #{set1.class.name} #{set1.inspect}, #{op}, #{set2.class.name} #{set2.inspect}"
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
          #puts "B = #{b.inspect}"
          for v in a
            #puts "v = #{v.inspect}"
            v = Functions::number(v)
            #puts "v = #{v.inspect}"
            #puts compare(v,op,b)
            return true if compare( v, op, b )
          end
        else
					#puts "Functions::string( #{b}(#{b.class.name}) ) = #{Functions::string(b)}"
          b = Functions::string( b )
          for v in a
						#puts "v = #{v.class.name} #{v.inspect}"
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
        #puts ">>> #{compare( set1, op, set2 )}"
        return compare( set1, op, set2 )
      end
      return false
    end

    def compare a, op, b
			#puts "COMPARE #{a.to_s}(#{a.class.name}) #{op} #{b.to_s}(#{a.class.name})"
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
