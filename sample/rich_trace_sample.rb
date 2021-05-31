def check
  foo = "foo"
  bar = nil   # accidentally nil
  baz = "baz"

  puts(foo.upcase, bar.upcase, baz.upcase)
end

begin
  check
rescue Exception
  find_node_by_id = -> id, node {
    return nil unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
    return node if node.node_id == id
    node.children.each do |child_node|
      ret = find_node_by_id[id, child_node]
      return ret if ret
    end
    return nil
  }

  root_node =

  $!.full_message.lines.zip($!.backtrace_locations) do |line, loc|
    puts line
    node = find_node_by_id[loc.node_id, RubyVM::AbstractSyntaxTree.parse_file(loc.path)]
    if File.readable?(loc.path)
      lines = File.foreach(loc.path).to_a[node.first_lineno - 1 .. node.last_lineno - 1]
      lines[-1][node.last_column, 0] = "\e[0m"
      lines[0][node.first_column, 0] = "\e[4m"
      puts
      lines.each {|line| puts "> " + line }
      puts
    end
  end
end
