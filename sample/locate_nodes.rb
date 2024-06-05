# This script locates a set of nodes determined by a line and column (in bytes).

require "prism"

def locate(node, line:, column:)
  queue = [node]
  result = []

  while (node = queue.shift)
    # Each node that we visit should be added to the result, so that we end up
    # with an array of the nodes that we traversed.
    result << node

    # Iterate over each child node.
    node.compact_child_nodes.each do |child_node|
      child_location = child_node.location

      start_line = child_location.start_line
      end_line = child_location.end_line

      # Here we determine if the given coordinates are contained within the
      # child node's location.
      if start_line == end_line
        if line == start_line && column >= child_location.start_column && column < child_location.end_column
          queue << child_node
          break
        end
      elsif (line == start_line && column >= child_location.start_column) || (line == end_line && column < child_location.end_column)
        queue << child_node
        break
      elsif line > start_line && line < end_line
        queue << child_node
        break
      end
    end
  end

  # Finally, we return the result.
  result
end

result = Prism.parse_stream(DATA)
locate(result.value, line: 4, column: 14).each_with_index do |node, index|
  location = node.location
  puts "#{" " * index}#{node.type}@#{location.start_line}:#{location.start_column}-#{location.end_line}:#{location.end_column}"
end

# =>
# program_node@1:0-7:3
#  statements_node@1:0-7:3
#   module_node@1:0-7:3
#    statements_node@2:2-6:5
#     class_node@2:2-6:5
#      statements_node@3:4-5:7
#       def_node@3:4-5:7
#        statements_node@4:6-4:21
#         call_node@4:6-4:21
#          call_node@4:6-4:15
#           arguments_node@4:12-4:15
#            integer_node@4:12-4:15

__END__
module Foo
  class Bar
    def baz
      111 + 222 + 333
    end
  end
end
