module Ruby
  module Signature
    class ConstantTable
      attr_reader :definition_builder
      attr_reader :constant_scopes_cache

      def env
        definition_builder.env
      end

      def initialize(builder:)
        @definition_builder = builder
        @constant_scopes_cache = {}
      end

      def name_to_constant(name)
        case
        when env.name_to_constant.key?(name)
          decl = env.name_to_constant[name]
          type = env.absolute_type(decl.type, namespace: name.namespace) {|type| type.name.absolute! }
          Constant.new(name: name, type: type, declaration: decl)
        when env.class?(name)
          decl = env.name_to_decl[name]
          type = Types::ClassSingleton.new(name: name, location: nil)
          Constant.new(name: name, type: type, declaration: decl)
        end
      end

      def split_name(name)
        name.namespace.path + [name.name]
      end

      def resolve_constant_reference(name, context:)
        head, *tail = split_name(name)

        head_constant = case
                        when name.absolute?
                          name_to_constant(TypeName.new(name: head, namespace: Namespace.root))
                        when !context || context.empty?
                          name_to_constant(TypeName.new(name: head, namespace: Namespace.root))
                        else
                          resolve_constant_reference_context(head, context: context) ||
                            resolve_constant_reference_inherit(head,
                                                               scopes: constant_scopes(context.to_type_name))
                        end

        if head_constant
          tail.inject(head_constant) do |constant, name|
            resolve_constant_reference_inherit name,
                                               scopes: constant_scopes(constant.name),
                                               no_object: constant.name != BuiltinNames::Object.name
          end
        end
      end

      def resolve_constant_reference_context(name, context:)
        if context.empty?
          nil
        else
          name_to_constant(TypeName.new(name: name, namespace: context)) ||
            resolve_constant_reference_context(name, context: context.parent)
        end
      end

      def resolve_constant_reference_inherit(name, scopes:, no_object: false)
        scopes.each do |context|
          if context.path == [:Object]
            unless no_object
              constant = name_to_constant(TypeName.new(name: name, namespace: context)) ||
                name_to_constant(TypeName.new(name: name, namespace: Namespace.root))
            end
          else
            constant = name_to_constant(TypeName.new(name: name, namespace: context))
          end

          return constant if constant
        end

        nil
      end

      def constant_scopes(name)
        constant_scopes_cache[name] ||= constant_scopes0(name, scopes: [])
      end

      def constant_scopes_module(name, scopes:)
        decl = env.find_class(name)
        namespace = name.to_namespace

        decl.members.each do |member|
          case member
          when AST::Members::Include
            constant_scopes_module absolute_type_name(member.name, namespace: namespace),
                                   scopes: scopes
          end
        end

        scopes.unshift namespace
      end

      def constant_scopes0(name, scopes: [])
        decl = env.find_class(name)
        namespace = name.to_namespace

        case decl
        when AST::Declarations::Module
          constant_scopes0 BuiltinNames::Module.name, scopes: scopes
          constant_scopes_module name, scopes: scopes

        when AST::Declarations::Class
          unless name == BuiltinNames::BasicObject.name
            super_name = decl.super_class&.yield_self {|super_class|
              absolute_type_name(super_class.name, namespace: namespace)
            } || BuiltinNames::Object.name

            constant_scopes0 super_name, scopes: scopes
          end

          decl.members.each do |member|
            case member
            when AST::Members::Include
              constant_scopes_module absolute_type_name(member.name, namespace: namespace),
                                     scopes: scopes
            end
          end

          scopes.unshift namespace
        else
          raise "Unexpected declaration: #{name}"
        end

        env.each_extension(name).sort_by {|e| e.extension_name.to_s }.each do |extension|
          extension.members.each do |member|
            case member
            when AST::Members::Include
              constant_scopes_module absolute_type_name(member.name, namespace: namespace),
                                     scopes: []
            end
          end
        end

        scopes
      end

      def absolute_type_name(name, namespace:)
        env.absolute_type_name(name, namespace: namespace) do
          raise
        end
      end
    end
  end
end
