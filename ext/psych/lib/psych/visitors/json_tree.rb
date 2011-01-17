module Psych
  module Visitors
    class JSONTree < YAMLTree
      def initialize options = {}, emitter = Psych::JSON::TreeBuilder.new
        super
      end

      def visit_String o
        @emitter.scalar o.to_s, nil, nil, false, true, Nodes::Scalar::DOUBLE_QUOTED
      end
      alias :visit_Symbol :visit_String
    end
  end
end
