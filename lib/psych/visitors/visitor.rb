module Psych
  module Visitors
    class Visitor
      def accept target
        case target
        when Psych::Nodes::Scalar   then visit_Psych_Nodes_Scalar target
        when Psych::Nodes::Mapping  then visit_Psych_Nodes_Mapping target
        when Psych::Nodes::Sequence then visit_Psych_Nodes_Sequence target
        when Psych::Nodes::Alias    then visit_Psych_Nodes_Alias target
        when Psych::Nodes::Document then visit_Psych_Nodes_Document target
        when Psych::Nodes::Stream   then visit_Psych_Nodes_Stream target
        else
          raise "Can't handle #{target}"
        end
      end
    end
  end
end
