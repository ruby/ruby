module Psych
  module JSON
    ###
    # Psych::JSON::TreeBuilder is an event based AST builder.  Events are sent
    # to an instance of Psych::JSON::TreeBuilder and a JSON AST is constructed.
    class TreeBuilder < Psych::TreeBuilder
      def start_document version, tag_directives, implicit
        super(version, tag_directives, !streaming?)
      end

      def end_document implicit_end = !streaming?
        super(implicit_end)
      end

      def start_mapping anchor, tag, implicit, style
        super(anchor, nil, implicit, Nodes::Mapping::FLOW)
      end

      def start_sequence anchor, tag, implicit, style
        super(anchor, nil, implicit, Nodes::Sequence::FLOW)
      end

      def scalar value, anchor, tag, plain, quoted, style
        if "tag:yaml.org,2002:null" == tag
          super('null', nil, nil, true, false, Nodes::Scalar::PLAIN)
        else
          super
        end
      end
    end
  end
end
