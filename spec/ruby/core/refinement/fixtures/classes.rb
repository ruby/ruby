module RefinementSpec

  module ModuleWithAncestors
    include Module.new do
      def indent(level)
        " " * level + self
      end
    end
  end
end
