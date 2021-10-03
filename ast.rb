# for ast.c

# AbstractSyntaxTree provides methods to parse Ruby code into
# abstract syntax trees. The nodes in the tree
# are instances of RubyVM::AbstractSyntaxTree::Node.
#
# This module is MRI specific as it exposes implementation details
# of the MRI abstract syntax tree.
#
# This module is experimental and its API is not stable, therefore it might
# change without notice. As examples, the order of children nodes is not
# guaranteed, the number of children nodes might change, there is no way to
# access children nodes by name, etc.
#
# If you are looking for a stable API or an API working under multiple Ruby
# implementations, consider using the _parser_ gem or Ripper. If you would
# like to make RubyVM::AbstractSyntaxTree stable, please join the discussion
# at https://bugs.ruby-lang.org/issues/14844.
#
module RubyVM::AbstractSyntaxTree

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
  def self.parse string, keep_script_lines: false
    Primitive.ast_s_parse string, keep_script_lines
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
  def self.parse_file pathname, keep_script_lines: false
    Primitive.ast_s_parse_file pathname, keep_script_lines
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
  def self.of body, keep_script_lines: false
    Primitive.ast_s_of body, keep_script_lines
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
    #    lasgn = root.children[2]
    #    lasgn.type # => :LASGN
    #    call = lasgn.children[1]
    #    call.type # => :OPCALL
    def type
      Primitive.ast_node_type
    end

    #  call-seq:
    #     node.first_lineno -> integer
    #
    #  The line number in the source code where this AST's text began.
    def first_lineno
      Primitive.ast_node_first_lineno
    end

    #  call-seq:
    #     node.first_column -> integer
    #
    #  The column number in the source code where this AST's text began.
    def first_column
      Primitive.ast_node_first_column
    end

    #  call-seq:
    #     node.last_lineno -> integer
    #
    #  The line number in the source code where this AST's text ended.
    def last_lineno
      Primitive.ast_node_last_lineno
    end

    #  call-seq:
    #     node.last_column -> integer
    #
    #  The column number in the source code where this AST's text ended.
    def last_column
      Primitive.ast_node_last_column
    end

    #  call-seq:
    #     node.children -> array
    #
    #  Returns AST nodes under this one.  Each kind of node
    #  has different children, depending on what kind of node it is.
    #
    #  The returned array may contain other nodes or <code>nil</code>.
    def children
      Primitive.ast_node_children
    end

    #  call-seq:
    #     node.inspect -> string
    #
    #  Returns debugging information about this node as a string.
    def inspect
      Primitive.ast_node_inspect
    end

    #  call-seq:
    #     node.node_id -> integer
    #
    #  Returns an internal node_id number.
    #  Note that this is an API for ruby internal use, debugging,
    #  and research. Do not use this for any other purpose.
    #  The compatibility is not guaranteed.
    def node_id
      Primitive.ast_node_node_id
    end

    #  call-seq:
    #     node.script_lines -> array
    #
    #  Returns the original source code as an array of lines.
    #
    #  Note that this is an API for ruby internal use, debugging,
    #  and research. Do not use this for any other purpose.
    #  The compatibility is not guaranteed.
    def script_lines
      Primitive.ast_node_script_lines
    end

    #  call-seq:
    #     node.source -> string
    #
    #  Returns the code fragment that corresponds to this AST.
    #
    #  Note that this is an API for ruby internal use, debugging,
    #  and research. Do not use this for any other purpose.
    #  The compatibility is not guaranteed.
    #
    #  Also note that this API may return an incomplete code fragment
    #  that does not parse; for example, a here document following
    #  an expression may be dropped.
    def source
      lines = script_lines
      if lines
        lines = lines[first_lineno - 1 .. last_lineno - 1]
        lines[-1] = lines[-1][0...last_column]
        lines[0] = lines[0][first_column..-1]
        lines.join
      else
        nil
      end
    end
  end
end
