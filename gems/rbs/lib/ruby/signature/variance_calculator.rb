module Ruby
  module Signature
    class VarianceCalculator
      class Result
        attr_reader :result

        def initialize(variables:)
          @result = {}
          variables.each do |x|
            result[x] = :unused
          end
        end

        def covariant(x)
          case result[x]
          when :unused
            result[x] = :covariant
          when :contravariant
            result[x] = :invariant
          end
        end

        def contravariant(x)
          case result[x]
          when :unused
            result[x] = :contravariant
          when :covariant
            result[x] = :invariant
          end
        end

        def invariant(x)
          result[x] = :invariant
        end

        def each(&block)
          result.each(&block)
        end

        def include?(name)
          result.key?(name)
        end

        def compatible?(var, with_annotation:)
          variance = result[var]

          case
          when variance == :unused
            true
          when with_annotation == :invariant
            true
          when variance == with_annotation
            true
          else
            false
          end
        end
      end

      attr_reader :builder

      def initialize(builder:)
        @builder = builder
      end

      def env
        builder.env
      end

      def in_method_type(method_type:, variables:)
        result = Result.new(variables: variables)

        method_type.type.each_param do |param|
          type(param.type, result: result, context: :contravariant)
        end

        if method_type.block
          method_type.block.type.each_param do |param|
            type(param.type, result: result, context: :covariant)
          end
          type(method_type.block.type.return_type, result: result, context: :contravariant)
        end

        type(method_type.type.return_type, result: result, context: :covariant)

        result
      end

      def in_inherit(name:, args:, variables:)
        type = Types::ClassInstance.new(name: name, args: args, location: nil)

        Result.new(variables: variables).tap do |result|
          type(type, result: result, context: :covariant)
        end
      end

      def type(type, result:, context:)
        case type
        when Types::Variable
          if result.include?(type.name)
            case context
            when :covariant
              result.covariant(type.name)
            when :contravariant
              result.contravariant(type.name)
            when :invariant
              result.invariant(type.name)
            end
          end
        when Types::ClassInstance, Types::Interface
          decl = env.find_class(type.name)
          type.args.each.with_index do |ty, i|
            var = decl.type_params.params[i]
            case var.variance
            when :invariant
              type(ty, result: result, context: :invariant)
            when :covariant
              type(ty, result: result, context: context)
            when :contravariant
              con = case context
                    when :invariant
                      :invariant
                    when :covariant
                      :contravariant
                    when :contravariant
                      :covariant
                    end
              type(ty, result: result, context: con)
            end
          end
        when Types::Tuple, Types::Record, Types::Union, Types::Intersection
          # Covariant types
          type.each_type do |ty|
            type(ty, result: result, context: context)
          end
        end
      end
    end
  end
end
