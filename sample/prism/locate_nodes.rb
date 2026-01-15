# This script locates a set of nodes determined by a line and column (in bytes).

require "prism"
require "pp"

# This method determines if the given location covers the given line and column.
# It's important to note that columns (and offsets) in prism are always in
# bytes. This is because prism supports all 90 source encodings that Ruby
# supports. You can always retrieve the column (or offset) of a location in
# other units with other provided APIs, like #start_character_column or
# #start_code_units_column.
def covers?(location, line:, column:)
  start_line = location.start_line
  end_line = location.end_line

  if start_line == end_line
    # If the location only spans one line, then we only check if the line
    # matches and that the column is covered by the column range.
    line == start_line && (location.start_column...location.end_column).cover?(column)
  else
    # Otherwise, we check that it is on the start line and the column is greater
    # than or equal to the start column, or that it is on the end line and the
    # column is less than the end column, or that it is between the start and
    # end lines.
    (line == start_line && column >= location.start_column) ||
      (line == end_line && column < location.end_column) ||
      (line > start_line && line < end_line)
  end
end

# This method descends down into the AST whose root is `node` and returns the
# array of all of the nodes that cover the given line and column.
def locate(node, line:, column:)
  queue = [node]
  result = []

  # We could use a recursive method here instead if we wanted, but it's
  # important to note that that will not work for ASTs that are nested deeply
  # enough to cause a stack overflow.
  while (node = queue.shift)
    result << node

    # Nodes have `child_nodes` and `compact_child_nodes`. `child_nodes` have
    # consistent indices but include `nil` for optional fields that are not
    # present, whereas `compact_child_nodes` has inconsistent indices but does
    # not include `nil` for optional fields that are not present.
    node.compact_child_nodes.find do |child|
      queue << child if covers?(child.location, line: line, column: column)
    end
  end

  result
end

result = Prism.parse_stream(DATA)
locate(result.value, line: 4, column: 14).each_with_index do |node, index|
  print " " * index
  print node.class.name.split("::", 2).last
  print " "
  puts PP.pp(node.location, +"")
end

# =>
# ProgramNode (1,0)-(7,3)
#  StatementsNode (1,0)-(7,3)
#   ModuleNode (1,0)-(7,3)
#    StatementsNode (2,2)-(6,5)
#     ClassNode (2,2)-(6,5)
#      StatementsNode (3,4)-(5,7)
#       DefNode (3,4)-(5,7)
#        StatementsNode (4,6)-(4,21)
#         CallNode (4,6)-(4,21)
#          CallNode (4,6)-(4,15)
#           ArgumentsNode (4,12)-(4,15)
#            IntegerNode (4,12)-(4,15)

__END__
module Foo
  class Bar
    def baz
      111 + 222 + 333
    end
  end
end
