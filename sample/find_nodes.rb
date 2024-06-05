# This script finds all of the nodes of a specific type within a given source
# file. It uses the visitor class to traverse the AST.

require "prism"

class RegexpVisitor < Prism::Visitor
  def initialize(regexps)
    @regexps = regexps
  end

  def visit_regular_expression_node(node)
    @regexps << node
    super
  end
end

result = Prism.parse_stream(DATA)
regexps = []

result.value.accept(RegexpVisitor.new(regexps))
puts regexps.map(&:inspect)

# =>
# @ RegularExpressionNode (location: (2,9)-(2,14))
# ├── flags: forced_us_ascii_encoding
# ├── opening_loc: (2,9)-(2,10) = "/"
# ├── content_loc: (2,10)-(2,13) = "foo"
# ├── closing_loc: (2,13)-(2,14) = "/"
# └── unescaped: "foo"
# @ RegularExpressionNode (location: (3,9)-(3,14))
# ├── flags: forced_us_ascii_encoding
# ├── opening_loc: (3,9)-(3,10) = "/"
# ├── content_loc: (3,10)-(3,13) = "bar"
# ├── closing_loc: (3,13)-(3,14) = "/"
# └── unescaped: "bar"

__END__
class Foo
  REG1 = /foo/
  REG2 = /bar/
end
