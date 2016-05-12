# frozen_string_literal: false
require 'rexml/namespace'
require 'rexml/xmltokens'

module REXML
  module Parsers
    # You don't want to use this class.  Really.  Use XPath, which is a wrapper
    # for this class.  Believe me.  You don't want to poke around in here.
    # There is strange, dark magic at work in this code.  Beware.  Go back!  Go
    # back while you still can!
    class XPathParser
      include XMLTokens
      LITERAL    = /^'([^']*)'|^"([^"]*)"/u

      def namespaces=( namespaces )
        Functions::namespace_context = namespaces
        @namespaces = namespaces
      end

      def parse path
        path = path.dup
        path.gsub!(/([\(\[])\s+/, '\1') # Strip ignorable spaces
        path.gsub!( /\s+([\]\)])/, '\1')
        parsed = []
        OrExpr(path, parsed)
        parsed
      end

      def predicate path
        parsed = []
        Predicate( "[#{path}]", parsed )
        parsed
      end

      def abbreviate( path )
        path = path.kind_of?(String) ? parse( path ) : path
        string = ""
        document = false
        while path.size > 0
          op = path.shift
          case op
          when :node
          when :attribute
            string << "/" if string.size > 0
            string << "@"
          when :child
            string << "/" if string.size > 0
          when :descendant_or_self
            string << "/"
          when :self
            string << "."
          when :parent
            string << ".."
          when :any
            string << "*"
          when :text
            string << "text()"
          when :following, :following_sibling,
                :ancestor, :ancestor_or_self, :descendant,
                :namespace, :preceding, :preceding_sibling
            string << "/" unless string.size == 0
            string << op.to_s.tr("_", "-")
            string << "::"
          when :qname
            prefix = path.shift
            name = path.shift
            string << prefix+":" if prefix.size > 0
            string << name
          when :predicate
            string << '['
            string << predicate_to_string( path.shift ) {|x| abbreviate( x ) }
            string << ']'
          when :document
            document = true
          when :function
            string << path.shift
            string << "( "
            string << predicate_to_string( path.shift[0] ) {|x| abbreviate( x )}
            string << " )"
          when :literal
            string << %Q{ "#{path.shift}" }
          else
            string << "/" unless string.size == 0
            string << "UNKNOWN("
            string << op.inspect
            string << ")"
          end
        end
        string = "/"+string if document
        return string
      end

      def expand( path )
        path = path.kind_of?(String) ? parse( path ) : path
        string = ""
        document = false
        while path.size > 0
          op = path.shift
          case op
          when :node
            string << "node()"
          when :attribute, :child, :following, :following_sibling,
                :ancestor, :ancestor_or_self, :descendant, :descendant_or_self,
                :namespace, :preceding, :preceding_sibling, :self, :parent
            string << "/" unless string.size == 0
            string << op.to_s.tr("_", "-")
            string << "::"
          when :any
            string << "*"
          when :qname
            prefix = path.shift
            name = path.shift
            string << prefix+":" if prefix.size > 0
            string << name
          when :predicate
            string << '['
            string << predicate_to_string( path.shift ) { |x| expand(x) }
            string << ']'
          when :document
            document = true
          else
            string << "/" unless string.size == 0
            string << "UNKNOWN("
            string << op.inspect
            string << ")"
          end
        end
        string = "/"+string if document
        return string
      end

      def predicate_to_string( path, &block )
        string = ""
        case path[0]
        when :and, :or, :mult, :plus, :minus, :neq, :eq, :lt, :gt, :lteq, :gteq, :div, :mod, :union
          op = path.shift
          case op
          when :eq
            op = "="
          when :lt
            op = "<"
          when :gt
            op = ">"
          when :lteq
            op = "<="
          when :gteq
            op = ">="
          when :neq
            op = "!="
          when :union
            op = "|"
          end
          left = predicate_to_string( path.shift, &block )
          right = predicate_to_string( path.shift, &block )
          string << " "
          string << left
          string << " "
          string << op.to_s
          string << " "
          string << right
          string << " "
        when :function
          path.shift
          name = path.shift
          string << name
          string << "( "
          string << predicate_to_string( path.shift, &block )
          string << " )"
        when :literal
          path.shift
          string << " "
          string << path.shift.inspect
          string << " "
        else
          string << " "
          string << yield( path )
          string << " "
        end
        return string.squeeze(" ")
      end

      private
      #LocationPath
      #  | RelativeLocationPath
      #  | '/' RelativeLocationPath?
      #  | '//' RelativeLocationPath
      def LocationPath path, parsed
        path = path.strip
        if path[0] == ?/
          parsed << :document
          if path[1] == ?/
            parsed << :descendant_or_self
            parsed << :node
            path = path[2..-1]
          else
            path = path[1..-1]
          end
        end
        return RelativeLocationPath( path, parsed ) if path.size > 0
      end

      #RelativeLocationPath
      #  |                                                    Step
      #    | (AXIS_NAME '::' | '@' | '')                     AxisSpecifier
      #      NodeTest
      #        Predicate
      #    | '.' | '..'                                      AbbreviatedStep
      #  |  RelativeLocationPath '/' Step
      #  | RelativeLocationPath '//' Step
      AXIS = /^(ancestor|ancestor-or-self|attribute|child|descendant|descendant-or-self|following|following-sibling|namespace|parent|preceding|preceding-sibling|self)::/
      def RelativeLocationPath path, parsed
        while path.size > 0
          # (axis or @ or <child::>) nodetest predicate  >
          # OR                                          >  / Step
          # (. or ..)                                    >
          if path[0] == ?.
            if path[1] == ?.
              parsed << :parent
              parsed << :node
              path = path[2..-1]
            else
              parsed << :self
              parsed << :node
              path = path[1..-1]
            end
          else
            if path[0] == ?@
              parsed << :attribute
              path = path[1..-1]
              # Goto Nodetest
            elsif path =~ AXIS
              parsed << $1.tr('-','_').intern
              path = $'
              # Goto Nodetest
            else
              parsed << :child
            end

            n = []
            path = NodeTest( path, n)

            if path[0] == ?[
              path = Predicate( path, n )
            end

            parsed.concat(n)
          end

          if path.size > 0
            if path[0] == ?/
              if path[1] == ?/
                parsed << :descendant_or_self
                parsed << :node
                path = path[2..-1]
              else
                path = path[1..-1]
              end
            else
              return path
            end
          end
        end
        return path
      end

      # Returns a 1-1 map of the nodeset
      # The contents of the resulting array are either:
      #   true/false, if a positive match
      #   String, if a name match
      #NodeTest
      #  | ('*' | NCNAME ':' '*' | QNAME)                NameTest
      #  | NODE_TYPE '(' ')'                              NodeType
      #  | PI '(' LITERAL ')'                            PI
      #    | '[' expr ']'                                Predicate
      NCNAMETEST= /^(#{NCNAME_STR}):\*/u
      QNAME     = Namespace::NAMESPLIT
      NODE_TYPE  = /^(comment|text|node)\(\s*\)/m
      PI        = /^processing-instruction\(/
      def NodeTest path, parsed
        case path
        when /^\*/
          path = $'
          parsed << :any
        when NODE_TYPE
          type = $1
          path = $'
          parsed << type.tr('-', '_').intern
        when PI
          path = $'
          literal = nil
          if path !~ /^\s*\)/
            path =~ LITERAL
            literal = $1
            path = $'
            raise ParseException.new("Missing ')' after processing instruction") if path[0] != ?)
            path = path[1..-1]
          end
          parsed << :processing_instruction
          parsed << (literal || '')
        when NCNAMETEST
          prefix = $1
          path = $'
          parsed << :namespace
          parsed << prefix
        when QNAME
          prefix = $1
          name = $2
          path = $'
          prefix = "" unless prefix
          parsed << :qname
          parsed << prefix
          parsed << name
        end
        return path
      end

      # Filters the supplied nodeset on the predicate(s)
      def Predicate path, parsed
        return nil unless path[0] == ?[
        predicates = []
        while path[0] == ?[
          path, expr = get_group(path)
          predicates << expr[1..-2] if expr
        end
        predicates.each{ |pred|
          preds = []
          parsed << :predicate
          parsed << preds
          OrExpr(pred, preds)
        }
        path
      end

      # The following return arrays of true/false, a 1-1 mapping of the
      # supplied nodeset, except for axe(), which returns a filtered
      # nodeset

      #| OrExpr S 'or' S AndExpr
      #| AndExpr
      def OrExpr path, parsed
        n = []
        rest = AndExpr( path, n )
        if rest != path
          while rest =~ /^\s*( or )/
            n = [ :or, n, [] ]
            rest = AndExpr( $', n[-1] )
          end
        end
        if parsed.size == 0 and n.size != 0
          parsed.replace(n)
        elsif n.size > 0
          parsed << n
        end
        rest
      end

      #| AndExpr S 'and' S EqualityExpr
      #| EqualityExpr
      def AndExpr path, parsed
        n = []
        rest = EqualityExpr( path, n )
        if rest != path
          while rest =~ /^\s*( and )/
            n = [ :and, n, [] ]
            rest = EqualityExpr( $', n[-1] )
          end
        end
        if parsed.size == 0 and n.size != 0
          parsed.replace(n)
        elsif n.size > 0
          parsed << n
        end
        rest
      end

      #| EqualityExpr ('=' | '!=')  RelationalExpr
      #| RelationalExpr
      def EqualityExpr path, parsed
        n = []
        rest = RelationalExpr( path, n )
        if rest != path
          while rest =~ /^\s*(!?=)\s*/
            if $1[0] == ?!
              n = [ :neq, n, [] ]
            else
              n = [ :eq, n, [] ]
            end
            rest = RelationalExpr( $', n[-1] )
          end
        end
        if parsed.size == 0 and n.size != 0
          parsed.replace(n)
        elsif n.size > 0
          parsed << n
        end
        rest
      end

      #| RelationalExpr ('<' | '>' | '<=' | '>=') AdditiveExpr
      #| AdditiveExpr
      def RelationalExpr path, parsed
        n = []
        rest = AdditiveExpr( path, n )
        if rest != path
          while rest =~ /^\s*([<>]=?)\s*/
            if $1[0] == ?<
              sym = "lt"
            else
              sym = "gt"
            end
            sym << "eq" if $1[-1] == ?=
            n = [ sym.intern, n, [] ]
            rest = AdditiveExpr( $', n[-1] )
          end
        end
        if parsed.size == 0 and n.size != 0
          parsed.replace(n)
        elsif n.size > 0
          parsed << n
        end
        rest
      end

      #| AdditiveExpr ('+' | S '-') MultiplicativeExpr
      #| MultiplicativeExpr
      def AdditiveExpr path, parsed
        n = []
        rest = MultiplicativeExpr( path, n )
        if rest != path
          while rest =~ /^\s*(\+| -)\s*/
            if $1[0] == ?+
              n = [ :plus, n, [] ]
            else
              n = [ :minus, n, [] ]
            end
            rest = MultiplicativeExpr( $', n[-1] )
          end
        end
        if parsed.size == 0 and n.size != 0
          parsed.replace(n)
        elsif n.size > 0
          parsed << n
        end
        rest
      end

      #| MultiplicativeExpr ('*' | S ('div' | 'mod') S) UnaryExpr
      #| UnaryExpr
      def MultiplicativeExpr path, parsed
        n = []
        rest = UnaryExpr( path, n )
        if rest != path
          while rest =~ /^\s*(\*| div | mod )\s*/
            if $1[0] == ?*
              n = [ :mult, n, [] ]
            elsif $1.include?( "div" )
              n = [ :div, n, [] ]
            else
              n = [ :mod, n, [] ]
            end
            rest = UnaryExpr( $', n[-1] )
          end
        end
        if parsed.size == 0 and n.size != 0
          parsed.replace(n)
        elsif n.size > 0
          parsed << n
        end
        rest
      end

      #| '-' UnaryExpr
      #| UnionExpr
      def UnaryExpr path, parsed
        path =~ /^(\-*)/
        path = $'
        if $1 and (($1.size % 2) != 0)
          mult = -1
        else
          mult = 1
        end
        parsed << :neg if mult < 0

        n = []
        path = UnionExpr( path, n )
        parsed.concat( n )
        path
      end

      #| UnionExpr '|' PathExpr
      #| PathExpr
      def UnionExpr path, parsed
        n = []
        rest = PathExpr( path, n )
        if rest != path
          while rest =~ /^\s*(\|)\s*/
            n = [ :union, n, [] ]
            rest = PathExpr( $', n[-1] )
          end
        end
        if parsed.size == 0 and n.size != 0
          parsed.replace( n )
        elsif n.size > 0
          parsed << n
        end
        rest
      end

      #| LocationPath
      #| FilterExpr ('/' | '//') RelativeLocationPath
      def PathExpr path, parsed
        path =~ /^\s*/
        path = $'
        n = []
        rest = FilterExpr( path, n )
        if rest != path
          if rest and rest[0] == ?/
            return RelativeLocationPath(rest, n)
          end
        end
        rest = LocationPath(rest, n) if rest =~ /\A[\/\.\@\[\w*]/
        parsed.concat(n)
        return rest
      end

      #| FilterExpr Predicate
      #| PrimaryExpr
      def FilterExpr path, parsed
        n = []
        path = PrimaryExpr( path, n )
        path = Predicate(path, n) if path and path[0] == ?[
        parsed.concat(n)
        path
      end

      #| VARIABLE_REFERENCE
      #| '(' expr ')'
      #| LITERAL
      #| NUMBER
      #| FunctionCall
      VARIABLE_REFERENCE  = /^\$(#{NAME_STR})/u
      NUMBER              = /^(\d*\.?\d+)/
      NT        = /^comment|text|processing-instruction|node$/
      def PrimaryExpr path, parsed
        case path
        when VARIABLE_REFERENCE
          varname = $1
          path = $'
          parsed << :variable
          parsed << varname
          #arry << @variables[ varname ]
        when /^(\w[-\w]*)(?:\()/
          fname = $1
          tmp = $'
          return path if fname =~ NT
          path = tmp
          parsed << :function
          parsed << fname
          path = FunctionCall(path, parsed)
        when NUMBER
          varname = $1.nil? ? $2 : $1
          path = $'
          parsed << :literal
          parsed << (varname.include?('.') ? varname.to_f : varname.to_i)
        when LITERAL
          varname = $1.nil? ? $2 : $1
          path = $'
          parsed << :literal
          parsed << varname
        when /^\(/                                               #/
          path, contents = get_group(path)
          contents = contents[1..-2]
          n = []
          OrExpr( contents, n )
          parsed.concat(n)
        end
        path
      end

      #| FUNCTION_NAME '(' ( expr ( ',' expr )* )? ')'
      def FunctionCall rest, parsed
        path, arguments = parse_args(rest)
        argset = []
        for argument in arguments
          args = []
          OrExpr( argument, args )
          argset << args
        end
        parsed << argset
        path
      end

      # get_group( '[foo]bar' ) -> ['bar', '[foo]']
      def get_group string
        ind = 0
        depth = 0
        st = string[0,1]
        en = (st == "(" ? ")" : "]")
        begin
          case string[ind,1]
          when st
            depth += 1
          when en
            depth -= 1
          end
          ind += 1
        end while depth > 0 and ind < string.length
        return nil unless depth==0
        [string[ind..-1], string[0..ind-1]]
      end

      def parse_args( string )
        arguments = []
        ind = 0
        inquot = false
        inapos = false
        depth = 1
        begin
          case string[ind]
          when ?"
            inquot = !inquot unless inapos
          when ?'
            inapos = !inapos unless inquot
          else
            unless inquot or inapos
              case string[ind]
              when ?(
                depth += 1
                if depth == 1
                  string = string[1..-1]
                  ind -= 1
                end
              when ?)
                depth -= 1
                if depth == 0
                  s = string[0,ind].strip
                  arguments << s unless s == ""
                  string = string[ind+1..-1]
                end
              when ?,
                if depth == 1
                  s = string[0,ind].strip
                  arguments << s unless s == ""
                  string = string[ind+1..-1]
                  ind = -1
                end
              end
            end
          end
          ind += 1
        end while depth > 0 and ind < string.length
        return nil unless depth==0
        [string,arguments]
      end
    end
  end
end
