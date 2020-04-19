module Ruby
  module Signature
    class Substitution
      attr_reader :mapping

      def initialize()
        @mapping = {}
      end

      def add(from:, to:)
        mapping[from] = to
      end

      def self.build(variables, types, &block)
        unless variables.size == types.size
          raise "Broken substitution: variables=#{variables}, types=#{types}"
        end

        mapping = variables.zip(types).to_h

        self.new.tap do |subst|
          mapping.each do |v, t|
            type = block_given? ? yield(t) : t
            subst.add(from: v, to: type)
          end
        end
      end

      def apply(ty)
        case ty
        when Types::Variable
          mapping[ty.name] || ty
        else
          ty
        end
      end

      def without(*vars)
        self.class.new.tap do |subst|
          subst.mapping.merge!(mapping)
          vars.each do |var|
            subst.mapping.delete(var)
          end
        end
      end
    end
  end
end
