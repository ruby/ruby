# This script visits all of the nodes of a specific type within a given source
# file. It uses the visitor class to traverse the AST.

require "prism"
require "pp"

class CaseInsensitiveRegularExpressionVisitor < Prism::Visitor
  def initialize(regexps)
    @regexps = regexps
  end

  # As the visitor is walking the tree, this method will only be called when it
  # encounters a regular expression node. We can then call any regular
  # expression -specific APIs. In this case, we are only interested in the
  # regular expressions that are case-insensitive, which we can retrieve with
  # the #ignore_case? method.
  def visit_regular_expression_node(node)
    @regexps << node if node.ignore_case?
    super
  end

  def visit_interpolated_regular_expression_node(node)
    @regexps << node if node.ignore_case?

    # The default behavior of the visitor is to continue visiting the children
    # of the node. Because Ruby is so dynamic, it's actually possible for
    # another regular expression to be interpolated in statements contained
    # within the #{} contained in this interpolated regular expression node. By
    # calling `super`, we ensure the visitor will continue. Failing to call
    # `super` will cause the visitor to stop the traversal of the tree, which
    # can also be useful in some cases.
    super
  end
end

result = Prism.parse_stream(DATA)
regexps = []

result.value.accept(CaseInsensitiveRegularExpressionVisitor.new(regexps))
regexps.each do |node|
  print node.class.name.split("::", 2).last
  print " "
  puts PP.pp(node.location, +"")

  if node.is_a?(Prism::RegularExpressionNode)
    print "  "
    p node.unescaped
  end
end

# =>
# InterpolatedRegularExpressionNode (3,9)-(3,47)
# RegularExpressionNode (3,16)-(3,22)
#   "bar"
# RegularExpressionNode (4,9)-(4,15)
#   "bar"

__END__
class Foo
  REG1 = /foo/
  REG2 = /foo #{/bar/i =~ "" ? "bar" : "baz"}/i
  REG3 = /bar/i
end
