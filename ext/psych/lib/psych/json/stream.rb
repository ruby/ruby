module Psych
  module JSON
    class Stream < Psych::Stream
      class Emitter < Psych::Stream::Emitter # :nodoc:
        def start_document version, tag_directives, implicit
          super(version, tag_directives, !streaming?)
        end

        def start_mapping anchor, tag, implicit, style
          super(anchor, tag, implicit, Nodes::Mapping::FLOW)
        end

        def start_sequence anchor, tag, implicit, style
          super(anchor, tag, implicit, Nodes::Sequence::FLOW)
        end

        def scalar value, anchor, tag, plain, quoted, style
          if "tag:yaml.org,2002:null" == tag
            super('null', nil, nil, true, false, Nodes::Scalar::PLAIN)
          else
            super
          end
        end
      end

      def visit_String o
        @emitter.scalar o.to_s, nil, nil, false, true, Nodes::Scalar::ANY
      end
      alias :visit_Symbol :visit_String
    end
  end
end
