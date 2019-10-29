# frozen-string-literal: true

require_relative '../levenshtein'

module DidYouMean
  module Experimental
    module InitializerNameCorrection
      def method_added(name)
        super

        distance = Levenshtein.distance(name.to_s, 'initialize')
        if distance != 0 && distance <= 2
          warn "warning: #{name} might be misspelled, perhaps you meant initialize?"
        end
      end
    end

    ::Class.prepend(InitializerNameCorrection)
  end
end
