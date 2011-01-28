module Psych
  module Visitors
    class JSONTree < YAMLTree
      def initialize options = {}, emitter = Psych::JSON::TreeBuilder.new
        super
      end

      def visit_NilClass o
        @emitter.scalar 'null', nil, nil, true, false, Nodes::Scalar::PLAIN
      end

      def visit_Integer o
        @emitter.scalar o.to_s, nil, nil, true, false, Nodes::Scalar::PLAIN
      end

      def visit_Float o
        return super if o.nan? || o.infinite?
        visit_Integer o
      end

      def visit_String o
        @emitter.scalar o.to_s, nil, nil, false, true, Nodes::Scalar::DOUBLE_QUOTED
      end
      alias :visit_Symbol :visit_String

      private
    end
  end
end
