module Psych
  module Visitors
    class JSONTree < YAMLTree
      def visit_NilClass o
        scalar = create_scalar(
          'null', nil, nil, true, false, Nodes::Scalar::PLAIN)
        append scalar
      end

      def visit_Integer o
        append create_scalar(o.to_s, nil, nil, true, false, Nodes::Scalar::PLAIN)
      end

      def visit_Float o
        return super if o.nan? || o.infinite?
        visit_Integer o
      end

      def visit_String o
        append create_scalar o.to_s
      end
      alias :visit_Symbol :visit_String

      private
      def create_document
        doc = super
        doc.implicit     = true
        doc.implicit_end = true
        doc
      end

      def create_mapping
        map = super
        map.style = Nodes::Mapping::FLOW
        map
      end

      def create_scalar value, anchor = nil, tag = nil, plain = false, quoted = true, style = Nodes::Scalar::ANY
        super
      end

      def create_sequence anchor = nil, tag = nil, implicit = true, style = Nodes::Sequence::FLOW
        super
      end
    end
  end
end
