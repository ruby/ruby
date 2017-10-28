module ModuleSpecs
  module EmptyRefinement
  end

  module RefinementForStringToS
    refine String do
      def to_s; "hello from refinement"; end
    end
  end
end
