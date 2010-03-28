module Psych
  module Visitors
    class JSONTree < YAMLTree
      def visit_Symbol o
        append create_scalar o.to_s
      end

      def visit_NilClass o
        scalar = Nodes::Scalar.new(
          'null', nil, nil, true, false, Nodes::Scalar::PLAIN)
        append scalar
      end

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
        super(value, anchor, tag, false, true, style)
      end

      def create_sequence anchor = nil, tag = nil, implicit = true, style = Nodes::Sequence::FLOW
        super
      end
    end
  end
end
