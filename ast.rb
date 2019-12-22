# for ast.c

class RubyVM

  # AbstractSyntaxTree provides methods to parse Ruby code into
  # abstract syntax trees. The nodes in the tree
  # are instances of RubyVM::AbstractSyntaxTree::Node.
  #
  # This class is MRI specific as it exposes implementation details
  # of the MRI abstract syntax tree.
  #
  # This class is experimental and its API is not stable, therefore it might
  # change without notice. As examples, the order of children nodes is not
  # guaranteed, the number of children nodes might change, there is no way to
  # access children nodes by name, etc.
  #
  # If you are looking for a stable API or an API working under multiple Ruby
  # implementations, consider using the _parser_ gem or Ripper. If you would
  # like to make RubyVM::AbstractSyntaxTree stable, please join the discussion
  # at https://bugs.ruby-lang.org/issues/14844.
  #
  module AbstractSyntaxTree

    #  call-seq:
    #     RubyVM::AbstractSyntaxTree.parse(string) -> RubyVM::AbstractSyntaxTree::Node
    #
    #  Parses the given _string_ into an abstract syntax tree,
    #  returning the root node of that tree.
    #
    #  SyntaxError is raised if the given _string_ is invalid syntax.
    #
    #    RubyVM::AbstractSyntaxTree.parse("x = 1 + 2")
    #    # => #<RubyVM::AbstractSyntaxTree::Node:SCOPE@1:0-1:9>
    def self.parse string
      __builtin_ast_s_parse string
    end

    #  call-seq:
    #     RubyVM::AbstractSyntaxTree.parse_file(pathname) -> RubyVM::AbstractSyntaxTree::Node
    #
    #   Reads the file from _pathname_, then parses it like ::parse,
    #   returning the root node of the abstract syntax tree.
    #
    #   SyntaxError is raised if _pathname_'s contents are not
    #   valid Ruby syntax.
    #
    #     RubyVM::AbstractSyntaxTree.parse_file("my-app/app.rb")
    #     # => #<RubyVM::AbstractSyntaxTree::Node:SCOPE@1:0-31:3>
    def self.parse_file pathname
      __builtin_ast_s_parse_file pathname
    end

    #  call-seq:
    #     RubyVM::AbstractSyntaxTree.of(proc)   -> RubyVM::AbstractSyntaxTree::Node
    #     RubyVM::AbstractSyntaxTree.of(method) -> RubyVM::AbstractSyntaxTree::Node
    #
    #   Returns AST nodes of the given _proc_ or _method_.
    #
    #     RubyVM::AbstractSyntaxTree.of(proc {1 + 2})
    #     # => #<RubyVM::AbstractSyntaxTree::Node:SCOPE@1:35-1:42>
    #
    #     def hello
    #       puts "hello, world"
    #     end
    #
    #     RubyVM::AbstractSyntaxTree.of(method(:hello))
    #     # => #<RubyVM::AbstractSyntaxTree::Node:SCOPE@1:0-3:3>
    def self.of body
      __builtin_ast_s_of body
    end

    # RubyVM::AbstractSyntaxTree::Node instances are created by parse methods in
    # RubyVM::AbstractSyntaxTree.
    #
    # This class is MRI specific.
    #
    class Node

      #  call-seq:
      #     node.type -> symbol
      #
      #  Returns the type of this node as a symbol.
      #
      #    root = RubyVM::AbstractSyntaxTree.parse("x = 1 + 2")
      #    root.type # => :SCOPE
      #    call = root.children[2]
      #    call.type # => :OPCALL
      def type
        __builtin_ast_node_type
      end

      #  call-seq:
      #     node.first_lineno -> integer
      #
      #  The line number in the source code where this AST's text began.
      def first_lineno
        __builtin_ast_node_first_lineno
      end

      #  call-seq:
      #     node.first_column -> integer
      #
      #  The column number in the source code where this AST's text began.
      def first_column
        __builtin_ast_node_first_column
      end

      #  call-seq:
      #     node.last_lineno -> integer
      #
      #  The line number in the source code where this AST's text ended.
      def last_lineno
        __builtin_ast_node_last_lineno
      end

      #  call-seq:
      #     node.last_column -> integer
      #
      #  The column number in the source code where this AST's text ended.
      def last_column
        __builtin_ast_node_last_column
      end

      #  call-seq:
      #     node.children -> array
      #
      #  Returns AST nodes under this one.  Each kind of node
      #  has different children, depending on what kind of node it is.
      #
      #  The returned array may contain other nodes or <code>nil</code>.
      def children
        __builtin_ast_node_children
      end

      #  call-seq:
      #     node.inspect -> string
      #
      #  Returns debugging information about this node as a string.
      def inspect
        __builtin_ast_node_inspect
      end
    end
  end
end
