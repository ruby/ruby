# This script finds calls to a specific method with a certain keyword parameter
# within a given source file.

require "prism"
require "pp"

# For deprecation or refactoring purposes, it's often useful to find all of the
# places that call a specific method with a specific k  eyword parameter. This is
# easily accomplished with a visitor such as this one.
class QuxParameterVisitor < Prism::Visitor
  def initialize(calls)
    @calls = calls
  end

  def visit_call_node(node)
    @calls << node if qux?(node)
    super
  end

  private

  def qux?(node)
    # All nodes implement pattern matching, so you can use the `in` operator to
    # pull out all of their individual fields. As you can see by this extensive
    # pattern match, this is quite a powerful feature.
    node in {
      # This checks that the receiver is the constant Qux or the constant path
      # ::Qux. We are assuming relative constants are fine in this case.
      receiver: (
        Prism::ConstantReadNode[name: :Qux] |
        Prism::ConstantPathNode[parent: nil, name: :Qux]
      ),
      # This checks that the name of the method is qux. We purposefully are not
      # checking the call operator (., ::, or &.) because we want all of them.
      # In other ASTs, this would be multiple node types, but prism combines
      # them all into one for convenience.
      name: :qux,
      arguments: Prism::ArgumentsNode[
        # Here we're going to use the "find" pattern to find the keyword hash
        # node that has the correct key.
        arguments: [
          *,
          Prism::KeywordHashNode[
            # Here we'll use another "find" pattern to find the key that we are
            # specifically looking for.
            elements: [
              *,
              # Finally, we can assert against the key itself. Note that we are
              # not looking at the value of hash pair, because we are only
              # specifically looking for a key.
              Prism::AssocNode[key: Prism::SymbolNode[unescaped: "qux"]],
              *
            ]
          ],
          *
        ]
      ]
    }
  end
end

calls = []
Prism.parse_stream(DATA).value.accept(QuxParameterVisitor.new(calls))

calls.each do |call|
  print "CallNode "
  puts PP.pp(call.location, +"")
  print "  "
  puts call.slice
end

# =>
# CallNode (5,6)-(5,29)
#   Qux.qux(222, qux: true)
# CallNode (9,6)-(9,30)
#   Qux&.qux(333, qux: true)
# CallNode (20,6)-(20,51)
#   Qux::qux(888, qux: ::Qux.qux(999, qux: true))
# CallNode (20,25)-(20,50)
#   ::Qux.qux(999, qux: true)

__END__
module Foo
  class Bar
    def baz1
      Qux.qux(111)
      Qux.qux(222, qux: true)
    end

    def baz2
      Qux&.qux(333, qux: true)
      Qux&.qux(444)
    end

    def baz3
      qux(555, qux: false)
      666.qux(666)
    end

    def baz4
      Qux::qux(777)
      Qux::qux(888, qux: ::Qux.qux(999, qux: true))
    end
  end
end
