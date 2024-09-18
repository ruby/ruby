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
  #     RubyVM::AbstractSyntaxTree.parse(string, keep_script_lines: RubyVM.keep_script_lines, error_tolerant: false, keep_tokens: false) -> RubyVM::AbstractSyntaxTree::Node
  #
  #  Parses the given _string_ into an abstract syntax tree,
  #  returning the root node of that tree.
  #
  #    RubyVM::AbstractSyntaxTree.parse("x = 1 + 2")
  #    # => #<RubyVM::AbstractSyntaxTree::Node:SCOPE@1:0-1:9>
  #
  #  If <tt>keep_script_lines: true</tt> option is provided, the text of the parsed
  #  source is associated with nodes and is available via Node#script_lines.
  #
  #  If <tt>keep_tokens: true</tt> option is provided, Node#tokens are populated.
  #
  #  SyntaxError is raised if the given _string_ is invalid syntax. To overwrite this
  #  behavior, <tt>error_tolerant: true</tt> can be provided. In this case, the parser
  #  will produce a tree where expressions with syntax errors would be represented by
  #  Node with <tt>type=:ERROR</tt>.
  #
  #     root = RubyVM::AbstractSyntaxTree.parse("x = 1; p(x; y=2")
  #     # <internal:ast>:33:in `parse': syntax error, unexpected ';', expecting ')' (SyntaxError)
  #     # x = 1; p(x; y=2
  #     #           ^
  #
  #     root = RubyVM::AbstractSyntaxTree.parse("x = 1; p(x; y=2", error_tolerant: true)
  #     # (SCOPE@1:0-1:15
  #     #  tbl: [:x, :y]
  #     #  args: nil
  #     #  body: (BLOCK@1:0-1:15 (LASGN@1:0-1:5 :x (LIT@1:4-1:5 1)) (ERROR@1:7-1:11) (LASGN@1:12-1:15 :y (LIT@1:14-1:15 2))))
  #     root.children.last.children
  #     # [(LASGN@1:0-1:5 :x (LIT@1:4-1:5 1)),
  #     #  (ERROR@1:7-1:11),
  #     #  (LASGN@1:12-1:15 :y (LIT@1:14-1:15 2))]
  #
  #  Note that parsing continues even after the errored expression.
  #
  def self.parse string, keep_script_lines: RubyVM.keep_script_lines, error_tolerant: false, keep_tokens: false
    Primitive.ast_s_parse string, keep_script_lines, error_tolerant, keep_tokens
  end

  #  call-seq:
  #     RubyVM::AbstractSyntaxTree.parse_file(pathname, keep_script_lines: RubyVM.keep_script_lines, error_tolerant: false, keep_tokens: false) -> RubyVM::AbstractSyntaxTree::Node
  #
  #   Reads the file from _pathname_, then parses it like ::parse,
  #   returning the root node of the abstract syntax tree.
  #
  #   SyntaxError is raised if _pathname_'s contents are not
  #   valid Ruby syntax.
  #
  #     RubyVM::AbstractSyntaxTree.parse_file("my-app/app.rb")
  #     # => #<RubyVM::AbstractSyntaxTree::Node:SCOPE@1:0-31:3>
  #
  #   See ::parse for explanation of keyword argument meaning and usage.
  def self.parse_file pathname, keep_script_lines: RubyVM.keep_script_lines, error_tolerant: false, keep_tokens: false
    Primitive.ast_s_parse_file pathname, keep_script_lines, error_tolerant, keep_tokens
  end

  #  call-seq:
  #     RubyVM::AbstractSyntaxTree.of(proc, keep_script_lines: RubyVM.keep_script_lines, error_tolerant: false, keep_tokens: false)   -> RubyVM::AbstractSyntaxTree::Node
  #     RubyVM::AbstractSyntaxTree.of(method, keep_script_lines: RubyVM.keep_script_lines, error_tolerant: false, keep_tokens: false) -> RubyVM::AbstractSyntaxTree::Node
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
  #
  #   See ::parse for explanation of keyword argument meaning and usage.
  def self.of body, keep_script_lines: RubyVM.keep_script_lines, error_tolerant: false, keep_tokens: false
    Primitive.ast_s_of body, keep_script_lines, error_tolerant, keep_tokens
  end

  #  call-seq:
  #     RubyVM::AbstractSyntaxTree.node_id_for_backtrace_location(backtrace_location)   -> integer
  #
  #   Returns the node id for the given backtrace location.
  #
  #     begin
  #       raise
  #     rescue =>  e
  #       loc = e.backtrace_locations.first
  #       RubyVM::AbstractSyntaxTree.node_id_for_backtrace_location(loc)
  #     end # => 0
  def self.node_id_for_backtrace_location backtrace_location
    Primitive.node_id_for_backtrace_location backtrace_location
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
    #     node.tokens -> array
    #
    #  Returns tokens corresponding to the location of the node.
    #  Returns +nil+ if +keep_tokens+ is not enabled when #parse method is called.
    #
    #    root = RubyVM::AbstractSyntaxTree.parse("x = 1 + 2", keep_tokens: true)
    #    root.tokens # => [[0, :tIDENTIFIER, "x", [1, 0, 1, 1]], [1, :tSP, " ", [1, 1, 1, 2]], ...]
    #    root.tokens.map{_1[2]}.join # => "x = 1 + 2"
    #
    #  Token is an array of:
    #
    #  - id
    #  - token type
    #  - source code text
    #  - location [ first_lineno, first_column, last_lineno, last_column ]
    def tokens
      return nil unless all_tokens

      all_tokens.each_with_object([]) do |token, a|
        loc = token.last
        if ([first_lineno, first_column] <=> [loc[0], loc[1]]) <= 0 &&
           ([last_lineno, last_column]   <=> [loc[2], loc[3]]) >= 0
           a << token
        end
      end
    end

    #  call-seq:
    #     node.all_tokens -> array
    #
    #  Returns all tokens for the input script regardless the receiver node.
    #  Returns +nil+ if +keep_tokens+ is not enabled when #parse method is called.
    #
    #    root = RubyVM::AbstractSyntaxTree.parse("x = 1 + 2", keep_tokens: true)
    #    root.all_tokens # => [[0, :tIDENTIFIER, "x", [1, 0, 1, 1]], [1, :tSP, " ", [1, 1, 1, 2]], ...]
    #    root.children[-1].all_tokens # => [[0, :tIDENTIFIER, "x", [1, 0, 1, 1]], [1, :tSP, " ", [1, 1, 1, 2]], ...]
    def all_tokens
      Primitive.ast_node_all_tokens
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
        lines[-1] = lines[-1].byteslice(0...last_column)
        lines[0] = lines[0].byteslice(first_column..-1)
        lines.join
      else
        nil
      end
    end

    #  call-seq:
    #     node.locations -> array
    #
    #  Returns location objects associated with the AST node.
    #  The returned array contains RubyVM::AbstractSyntaxTree::Location.
    def locations
      Primitive.ast_node_locations
    end
  end

  # RubyVM::AbstractSyntaxTree::Location instances are created by
  # RubyVM::AbstractSyntaxTree#locations.
  #
  # This class is MRI specific.
  #
  class Location

    #  call-seq:
    #     location.first_lineno -> integer
    #
    #  The line number in the source code where this AST's text began.
    def first_lineno
      Primitive.ast_location_first_lineno
    end

    #  call-seq:
    #     location.first_column -> integer
    #
    #  The column number in the source code where this AST's text began.
    def first_column
      Primitive.ast_location_first_column
    end

    #  call-seq:
    #     location.last_lineno -> integer
    #
    #  The line number in the source code where this AST's text ended.
    def last_lineno
      Primitive.ast_location_last_lineno
    end

    #  call-seq:
    #     location.last_column -> integer
    #
    #  The column number in the source code where this AST's text ended.
    def last_column
      Primitive.ast_location_last_column
    end

    #  call-seq:
    #     location.inspect -> string
    #
    #  Returns debugging information about this location as a string.
    def inspect
      Primitive.ast_location_inspect
    end
  end
end
