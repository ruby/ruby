require 'rexml/namespace'
require 'rexml/xmltokens'
require 'rexml/attribute'
require 'rexml/syncenumerator'
require 'rexml/parsers/xpathparser'

class Object
  # provides a unified +clone+ operation, for REXML::XPathParser
  # to use across multiple Object types
  def dclone
    clone
  end
end
class Symbol
  # provides a unified +clone+ operation, for REXML::XPathParser
  # to use across multiple Object types
  def dclone ; self ; end
end
class Fixnum
  # provides a unified +clone+ operation, for REXML::XPathParser
  # to use across multiple Object types
  def dclone ; self ; end
end
class Float
  # provides a unified +clone+ operation, for REXML::XPathParser
  # to use across multiple Object types
  def dclone ; self ; end
end
class Array
  # provides a unified +clone+ operation, for REXML::XPathParser
  # to use across multiple Object+ types
  def dclone
    klone = self.clone
    klone.clear
    self.each{|v| klone << v.dclone}
    klone
  end
end

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
      @namespaces = nil
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
      match( path_stack, nodeset )
    end

    def get_first path, nodeset
      path_stack = @parser.parse( path )
      first( path_stack, nodeset )
    end

    def predicate path, nodeset
      path_stack = @parser.parse( path )
      expr( path_stack, nodeset )
    end

    def []=( variable_name, value )
      @variables[ variable_name ] = value
    end


    # Performs a depth-first (document order) XPath search, and returns the
    # first match.  This is the fastest, lightest way to return a single result.
    #
    # FIXME: This method is incomplete!
    def first( path_stack, node )
      return nil if path.size == 0

      case path[0]
      when :document
        # do nothing
        return first( path[1..-1], node )
      when :child
        for c in node.children
          r = first( path[1..-1], c )
          return r if r
        end
      when :qname
        name = path[2]
        if node.name == name
          return node if path.size == 3
          return first( path[3..-1], node )
        else
          return nil
        end
      when :descendant_or_self
        r = first( path[1..-1], node )
        return r if r
        for c in node.children
          r = first( path, c )
          return r if r
        end
      when :node
        return first( path[1..-1], node )
      when :any
        return first( path[1..-1], node )
      end
      return nil
    end


    def match( path_stack, nodeset )
      r = expr( path_stack, nodeset )
      r
    end

    private


    # Returns a String namespace for a node, given a prefix
    # The rules are:
    #
    #  1. Use the supplied namespace mapping first.
    #  2. If no mapping was supplied, use the context node to look up the namespace
    def get_namespace( node, prefix )
      if @namespaces
        return @namespaces[prefix] || ''
      else
        return node.namespace( prefix ) if node.node_type == :element
        return ''
      end
    end


    # Expr takes a stack of path elements and a set of nodes (either a Parent
    # or an Array and returns an Array of matching nodes
    ALL = [ :attribute, :element, :text, :processing_instruction, :comment ]
    ELEMENTS = [ :element ]
    def expr( path_stack, nodeset, context=nil )
      node_types = ELEMENTS
      return nodeset if path_stack.length == 0 || nodeset.length == 0
      while path_stack.length > 0
        if nodeset.length == 0
          path_stack.clear
          return []
        end
        case (op = path_stack.shift)
        when :document
          nodeset = [ nodeset[0].root_node ]

        when :qname
          prefix = path_stack.shift
          name = path_stack.shift
          nodeset.delete_if do |node|
            # FIXME: This DOUBLES the time XPath searches take
            ns = get_namespace( node, prefix )
            if node.node_type == :element
              if node.name == name
              end
            end
            !(node.node_type == :element and
              node.name == name and
              node.namespace == ns )
          end
          node_types = ELEMENTS

        when :any
          nodeset.delete_if { |node| !node_types.include?(node.node_type) }

        when :self
          # This space left intentionally blank

        when :processing_instruction
          target = path_stack.shift
          nodeset.delete_if do |node|
            (node.node_type != :processing_instruction) or
            ( target!='' and ( node.target != target ) )
          end

        when :text
          nodeset.delete_if { |node| node.node_type != :text }

        when :comment
          nodeset.delete_if { |node| node.node_type != :comment }

        when :node
          # This space left intentionally blank
          node_types = ALL

        when :child
          new_nodeset = []
          nt = nil
          nodeset.each do |node|
            nt = node.node_type
            new_nodeset += node.children if nt == :element or nt == :document
          end
          nodeset = new_nodeset
          node_types = ELEMENTS

        when :literal
          return path_stack.shift

        when :attribute
          new_nodeset = []
          case path_stack.shift
          when :qname
            prefix = path_stack.shift
            name = path_stack.shift
            for element in nodeset
              if element.node_type == :element
                attrib = element.attribute( name, get_namespace(element, prefix) )
                new_nodeset << attrib if attrib
              end
            end
          when :any
            for element in nodeset
              if element.node_type == :element
                new_nodeset += element.attributes.to_a
              end
            end
          end
          nodeset = new_nodeset

        when :parent
          nodeset = nodeset.collect{|n| n.parent}.compact
          #nodeset = expr(path_stack.dclone, nodeset.collect{|n| n.parent}.compact)
          node_types = ELEMENTS

        when :ancestor
          new_nodeset = []
          nodeset.each do |node|
            while node.parent
              node = node.parent
              new_nodeset << node unless new_nodeset.include? node
            end
          end
          nodeset = new_nodeset
          node_types = ELEMENTS

        when :ancestor_or_self
          new_nodeset = []
          nodeset.each do |node|
            if node.node_type == :element
              new_nodeset << node
              while ( node.parent )
                node = node.parent
                new_nodeset << node unless new_nodeset.include? node
              end
            end
          end
          nodeset = new_nodeset
          node_types = ELEMENTS

        when :predicate
          new_nodeset = []
          subcontext = { :size => nodeset.size }
          pred = path_stack.shift
          nodeset.each_with_index { |node, index|
            subcontext[ :node ] = node
            subcontext[ :index ] = index+1
            pc = pred.dclone
            result = expr( pc, [node], subcontext )
            result = result[0] if result.kind_of? Array and result.length == 1
            if result.kind_of? Numeric
              new_nodeset << node if result == (index+1)
            elsif result.instance_of? Array
              if result.size > 0 and result.inject(false) {|k,s| s or k}
                new_nodeset << node if result.size > 0
              end
            else
              new_nodeset << node if result
            end
          }
          nodeset = new_nodeset
=begin
          predicate = path_stack.shift
          ns = nodeset.clone
          result = expr( predicate, ns )
          if result.kind_of? Array
            nodeset = result.zip(ns).collect{|m,n| n if m}.compact
          else
            nodeset = result ? nodeset : []
          end
=end

        when :descendant_or_self
          rv = descendant_or_self( path_stack, nodeset )
          path_stack.clear
          nodeset = rv
          node_types = ELEMENTS

        when :descendant
          results = []
          nt = nil
          nodeset.each do |node|
            nt = node.node_type
            results += expr( path_stack.dclone.unshift( :descendant_or_self ),
              node.children ) if nt == :element or nt == :document
          end
          nodeset = results
          node_types = ELEMENTS

        when :following_sibling
          results = []
          nodeset.each do |node|
            next if node.parent.nil?
            all_siblings = node.parent.children
            current_index = all_siblings.index( node )
            following_siblings = all_siblings[ current_index+1 .. -1 ]
            results += expr( path_stack.dclone, following_siblings )
          end
          nodeset = results

        when :preceding_sibling
          results = []
          nodeset.each do |node|
            next if node.parent.nil?
            all_siblings = node.parent.children
            current_index = all_siblings.index( node )
            preceding_siblings = all_siblings[ 0, current_index ].reverse
            results += preceding_siblings
          end
          nodeset = results
          node_types = ELEMENTS

        when :preceding
          new_nodeset = []
          nodeset.each do |node|
            new_nodeset += preceding( node )
          end
          nodeset = new_nodeset
          node_types = ELEMENTS

        when :following
          new_nodeset = []
          nodeset.each do |node|
            new_nodeset += following( node )
          end
          nodeset = new_nodeset
          node_types = ELEMENTS

        when :namespace
          new_nodeset = []
          prefix = path_stack.shift
          nodeset.each do |node|
            if (node.node_type == :element or node.node_type == :attribute)
              if @namespaces
                namespaces = @namespaces
              elsif (node.node_type == :element)
                namespaces = node.namespaces
              else
                namespaces = node.element.namesapces
              end
              if (node.namespace == namespaces[prefix])
                new_nodeset << node
              end
            end
          end
          nodeset = new_nodeset

        when :variable
          var_name = path_stack.shift
          return @variables[ var_name ]

        # :and, :or, :eq, :neq, :lt, :lteq, :gt, :gteq
        # TODO: Special case for :or and :and -- not evaluate the right
        # operand if the left alone determines result (i.e. is true for
        # :or and false for :and).
        when :eq, :neq, :lt, :lteq, :gt, :gteq, :or
          left = expr( path_stack.shift, nodeset.dup, context )
          right = expr( path_stack.shift, nodeset.dup, context )
          res = equality_relational_compare( left, op, right )
          return res

        when :and
          left = expr( path_stack.shift, nodeset.dup, context )
          return [] unless left
          if left.respond_to?(:inject) and !left.inject(false) {|a,b| a | b}
            return []
          end
          right = expr( path_stack.shift, nodeset.dup, context )
          res = equality_relational_compare( left, op, right )
          return res

        when :div
          left = Functions::number(expr(path_stack.shift, nodeset, context)).to_f
          right = Functions::number(expr(path_stack.shift, nodeset, context)).to_f
          return (left / right)

        when :mod
          left = Functions::number(expr(path_stack.shift, nodeset, context )).to_f
          right = Functions::number(expr(path_stack.shift, nodeset, context )).to_f
          return (left % right)

        when :mult
          left = Functions::number(expr(path_stack.shift, nodeset, context )).to_f
          right = Functions::number(expr(path_stack.shift, nodeset, context )).to_f
          return (left * right)

        when :plus
          left = Functions::number(expr(path_stack.shift, nodeset, context )).to_f
          right = Functions::number(expr(path_stack.shift, nodeset, context )).to_f
          return (left + right)

        when :minus
          left = Functions::number(expr(path_stack.shift, nodeset, context )).to_f
          right = Functions::number(expr(path_stack.shift, nodeset, context )).to_f
          return (left - right)

        when :union
          left = expr( path_stack.shift, nodeset, context )
          right = expr( path_stack.shift, nodeset, context )
          return (left | right)

        when :neg
          res = expr( path_stack, nodeset, context )
          return -(res.to_f)

        when :not
        when :function
          func_name = path_stack.shift.tr('-','_')
          arguments = path_stack.shift
          subcontext = context ? nil : { :size => nodeset.size }

          res = []
          cont = context
          nodeset.each_with_index { |n, i|
            if subcontext
              subcontext[:node]  = n
              subcontext[:index] = i
              cont = subcontext
            end
            arg_clone = arguments.dclone
            args = arg_clone.collect { |arg|
              expr( arg, [n], cont )
            }
            Functions.context = cont
            res << Functions.send( func_name, *args )
          }
          return res

        end
      end # while
      return nodeset
    end


    ##########################################################
    # FIXME
    # The next two methods are BAD MOJO!
    # This is my achilles heel.  If anybody thinks of a better
    # way of doing this, be my guest.  This really sucks, but
    # it is a wonder it works at all.
    # ########################################################

    def descendant_or_self( path_stack, nodeset )
      rs = []
      d_o_s( path_stack, nodeset, rs )
      document_order(rs.flatten.compact)
      #rs.flatten.compact
    end

    def d_o_s( p, ns, r )
      nt = nil
      ns.each_index do |i|
        n = ns[i]
        x = expr( p.dclone, [ n ] )
        nt = n.node_type
        d_o_s( p, n.children, x ) if nt == :element or nt == :document and n.children.size > 0
        r.concat(x) if x.size > 0
      end
    end


    # Reorders an array of nodes so that they are in document order
    # It tries to do this efficiently.
    #
    # FIXME: I need to get rid of this, but the issue is that most of the XPath
    # interpreter functions as a filter, which means that we lose context going
    # in and out of function calls.  If I knew what the index of the nodes was,
    # I wouldn't have to do this.  Maybe add a document IDX for each node?
    # Problems with mutable documents.  Or, rewrite everything.
    def document_order( array_of_nodes )
      new_arry = []
      array_of_nodes.each { |node|
        node_idx = []
        np = node.node_type == :attribute ? node.element : node
        while np.parent and np.parent.node_type == :element
          node_idx << np.parent.index( np )
          np = np.parent
        end
        new_arry << [ node_idx.reverse, node ]
      }
      new_arry.sort{ |s1, s2| s1[0] <=> s2[0] }.collect{ |s| s[1] }
    end


    def recurse( nodeset, &block )
      for node in nodeset
        yield node
        recurse( node, &block ) if node.node_type == :element
      end
    end



    # Builds a nodeset of all of the preceding nodes of the supplied node,
    # in reverse document order
    # preceding:: includes every element in the document that precedes this node,
    # except for ancestors
    def preceding( node )
      ancestors = []
      p = node.parent
      while p
        ancestors << p
        p = p.parent
      end

      acc = []
      p = preceding_node_of( node )
      while p
        if ancestors.include? p
          ancestors.delete(p)
        else
          acc << p
        end
        p = preceding_node_of( p )
      end
      acc
    end

    def preceding_node_of( node )
      psn = node.previous_sibling_node
      if psn.nil?
        if node.parent.nil? or node.parent.class == Document
          return nil
        end
        return node.parent
        #psn = preceding_node_of( node.parent )
      end
      while psn and psn.kind_of? Element and psn.children.size > 0
        psn = psn.children[-1]
      end
      psn
    end

    def following( node )
      acc = []
      p = next_sibling_node( node )
      while p
        acc << p
        p = following_node_of( p )
      end
      acc
    end

    def following_node_of( node )
      if node.kind_of? Element and node.children.size > 0
        return node.children[0]
      end
      return next_sibling_node(node)
    end

    def next_sibling_node(node)
      psn = node.next_sibling_node
      while psn.nil?
        if node.parent.nil? or node.parent.class == Document
          return nil
        end
        node = node.parent
        psn = node.next_sibling_node
      end
      return psn
    end

    def norm b
      case b
      when true, false
        return b
      when 'true', 'false'
        return Functions::boolean( b )
      when /^\d+(\.\d+)?$/
        return Functions::number( b )
      else
        return Functions::string( b )
      end
    end

    def equality_relational_compare( set1, op, set2 )
      if set1.kind_of? Array and set2.kind_of? Array
        if set1.size == 1 and set2.size == 1
          set1 = set1[0]
          set2 = set2[0]
        elsif set1.size == 0 or set2.size == 0
          nd = set1.size==0 ? set2 : set1
          rv = nd.collect { |il| compare( il, op, nil ) }
          return rv
        else
          res = []
          SyncEnumerator.new( set1, set2 ).each { |i1, i2|
            i1 = norm( i1 )
            i2 = norm( i2 )
            res << compare( i1, op, i2 )
          }
          return res
        end
      end
      # If one is nodeset and other is number, compare number to each item
      # in nodeset s.t. number op number(string(item))
      # If one is nodeset and other is string, compare string to each item
      # in nodeset s.t. string op string(item)
      # If one is nodeset and other is boolean, compare boolean to each item
      # in nodeset s.t. boolean op boolean(item)
      if set1.kind_of? Array or set2.kind_of? Array
        if set1.kind_of? Array
          a = set1
          b = set2
        else
          a = set2
          b = set1
        end

        case b
        when true, false
          return a.collect {|v| compare( Functions::boolean(v), op, b ) }
        when Numeric
          return a.collect {|v| compare( Functions::number(v), op, b )}
        when /^\d+(\.\d+)?$/
          b = Functions::number( b )
          return a.collect {|v| compare( Functions::number(v), op, b )}
        else
          b = Functions::string( b )
          return a.collect { |v| compare( Functions::string(v), op, b ) }
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
        if s1 == 'true' or s1 == 'false' or s2 == 'true' or s2 == 'false'
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
