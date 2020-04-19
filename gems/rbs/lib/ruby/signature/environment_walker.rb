module Ruby
  module Signature
    class EnvironmentWalker
      attr_reader :env

      def initialize(env:)
        @env = env
        @only_ancestors = nil
      end

      def builder
        @builder ||= DefinitionBuilder.new(env: env)
      end

      def only_ancestors!(only = true)
        @only_ancestors = only
        self
      end

      def only_ancestors?
        @only_ancestors
      end

      include TSort

      def tsort_each_node(&block)
        env.each_decl do |name|
          yield name.absolute!
        end

        env.each_alias do |name, _|
          yield name.absolute!
        end
      end

      def tsort_each_child(name, &block)
        unless name.namespace.empty?
          yield name.namespace.to_type_name
        end

        case
        when name.class?, name.interface?
          definitions = []

          case
          when name.class?
            definitions << builder.build_instance(name)
            definitions << builder.build_singleton(name)
          when name.interface?
            definitions << builder.build_interface(name, env.find_class(name))
          end

          definitions.each do |definition|
            definition.ancestors.each do |ancestor|
              yield ancestor.name

              case ancestor
              when Definition::Ancestor::Instance, Definition::Ancestor::ExtensionInstance
                ancestor.args.each do |type|
                  each_type_name type, &block
                end
              end
            end

            unless only_ancestors?
              definition.methods.each do |_, method|
                method.method_types.each do |method_type|
                  method_type.type.each_type do |type|
                    each_type_name type, &block
                  end
                  method_type.block&.type&.each_type do |type|
                    each_type_name type, &block
                  end
                end
              end
            end
          end
        when name.alias?
          each_type_name builder.expand_alias(name), &block
        end
      end

      def each_type_name(type, &block)
        case type
        when Ruby::Signature::Types::Bases::Any
        when Ruby::Signature::Types::Bases::Class
        when Ruby::Signature::Types::Bases::Instance
        when Ruby::Signature::Types::Bases::Self
        when Ruby::Signature::Types::Bases::Top
        when Ruby::Signature::Types::Bases::Bottom
        when Ruby::Signature::Types::Bases::Bool
        when Ruby::Signature::Types::Bases::Void
        when Ruby::Signature::Types::Bases::Nil
        when Ruby::Signature::Types::Variable
        when Ruby::Signature::Types::ClassSingleton
          yield type.name
        when Ruby::Signature::Types::ClassInstance, Ruby::Signature::Types::Interface
          yield type.name
          type.args.each do |ty|
            each_type_name(ty, &block)
          end
        when Ruby::Signature::Types::Alias
          yield type.name
        when Ruby::Signature::Types::Union, Ruby::Signature::Types::Intersection, Ruby::Signature::Types::Tuple
          type.types.each do |ty|
            each_type_name ty, &block
          end
        when Ruby::Signature::Types::Optional
          each_type_name type.type, &block
        when Ruby::Signature::Types::Literal
          # nop
        when Ruby::Signature::Types::Record
          type.fields.each_value do |ty|
            each_type_name ty, &block
          end
        when Ruby::Signature::Types::Proc
          type.each_type do |ty|
            each_type_name ty, &block
          end
        else
          raise "Unexpected type given: #{type}"
        end
      end
    end
  end
end
