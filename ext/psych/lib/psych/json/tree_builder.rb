module Psych
  module JSON
    ###
    # Psych::JSON::TreeBuilder is an event based AST builder.  Events are sent
    # to an instance of Psych::JSON::TreeBuilder and a JSON AST is constructed.
    class TreeBuilder < Psych::TreeBuilder
      def start_document version, tag_directives, implicit
        super(version, tag_directives, true)
      end

      def end_document implicit_end
        super(true)
      end

      def start_mapping anchor, tag, implicit, style
        super(anchor, tag, implicit, Nodes::Mapping::FLOW)
      end

      def start_sequence anchor, tag, implicit, style
        super(anchor, tag, implicit, Nodes::Sequence::FLOW)
      end
    end
  end
end
