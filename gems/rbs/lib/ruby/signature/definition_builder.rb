module Ruby
  module Signature
    class DefinitionBuilder
      attr_reader :env
      attr_reader :instance_cache
      attr_reader :singleton_cache

      def initialize(env:)
        @env = env
        @instance_cache = {}
        @singleton_cache = {}
      end

      def build_ancestors(self_ancestor, ancestors: [], building_ancestors: [], location: nil)
        decl = env.find_class(self_ancestor.name)
        namespace = self_ancestor.name.absolute!.to_namespace

        RecursiveAncestorError.check!(self_ancestor,
                                      ancestors: building_ancestors,
                                      location: location || decl.location)
        building_ancestors.push self_ancestor

        case self_ancestor
        when Definition::Ancestor::Instance
          args = self_ancestor.args
          param_names = decl.type_params.each.map(&:name)

          InvalidTypeApplicationError.check!(
            type_name: self_ancestor.name,
            args: args,
            params: decl.type_params,
            location: location || decl.location
          )

          sub = Substitution.build(param_names, args)

          case decl
          when AST::Declarations::Class
            unless self_ancestor.name == BuiltinNames::BasicObject.name
              super_ancestor = decl.super_class&.yield_self do |super_class|
                Definition::Ancestor::Instance.new(
                  name: absolute_type_name(super_class.name, namespace: namespace, location: location || decl.location),
                  args: super_class.args.map {|ty| absolute_type(ty.sub(sub), namespace: namespace) }
                )
              end || Definition::Ancestor::Instance.new(name: BuiltinNames::Object.name, args: [])

              build_ancestors(super_ancestor, ancestors: ancestors, building_ancestors: building_ancestors)
            end
          end

          decl.members.each do |member|
            case member
            when AST::Members::Include
              if member.name.class?
                ancestor = Definition::Ancestor::Instance.new(
                  name: absolute_type_name(member.name, namespace: namespace, location: member.location),
                  args: member.args.map {|ty| absolute_type(ty.sub(sub), namespace: namespace) }
                )
                build_ancestors ancestor, ancestors: ancestors, building_ancestors: building_ancestors, location: member.location
              end
            end
          end

          ancestors.unshift(self_ancestor)

          env.each_extension(self_ancestor.name).sort_by {|e| e.extension_name.to_s }.each do |extension|
            InvalidExtensionParameterError.check!(
              type_name: self_ancestor.name,
              extension_name: extension.extension_name,
              extension_params: extension.type_params,
              class_params: self_ancestor.args.map(&:name),
              location: extension.location
            )

            sub = Substitution.build(extension.type_params, self_ancestor.args)

            extension.members.each do |member|
              case member
              when AST::Members::Include
                if member.name.class?
                  ancestor = Definition::Ancestor::Instance.new(
                    name: absolute_type_name(member.name, namespace: namespace, location: member.location),
                    args: member.args.map {|ty| absolute_type(ty.sub(sub), namespace: namespace) }
                  )
                  build_ancestors ancestor, ancestors: ancestors, building_ancestors: building_ancestors, location: member.location
                end
              end
            end

            extension_ancestor = Definition::Ancestor::ExtensionInstance.new(
              name: extension.name.absolute!,
              extension_name: extension.extension_name,
              args: self_ancestor.args,
            )
            ancestors.unshift(extension_ancestor)

            extension.members.each do |member|
              case member
              when AST::Members::Prepend
                if member.name.class?
                  ancestor = Definition::Ancestor::Instance.new(
                    name: absolute_type_name(member.name, namespace: namespace, location: member.location),
                    args: member.args.map {|ty| absolute_type(ty.sub(sub), namespace: namespace) }
                  )
                  build_ancestors ancestor, ancestors: ancestors, building_ancestors: building_ancestors, location: member.location
                end
              end
            end
          end

          decl.members.each do |member|
            case member
            when AST::Members::Prepend
              ancestor = Definition::Ancestor::Instance.new(
                name: absolute_type_name(member.name, namespace: namespace, location: member.location),
                args: member.args.map {|ty| absolute_type(ty.sub(sub), namespace: namespace) }
              )
              build_ancestors ancestor, ancestors: ancestors, building_ancestors: building_ancestors, location: member.location
            end
          end
        when Definition::Ancestor::Singleton
          case decl
          when AST::Declarations::Class
            if self_ancestor.name == BuiltinNames::BasicObject.name
              class_ancestor = Definition::Ancestor::Instance.new(
                name: BuiltinNames::Class.name,
                args: []
              )
              build_ancestors class_ancestor, ancestors: ancestors, building_ancestors: building_ancestors
            else
              super_ancestor = decl.super_class&.yield_self do |super_class|
                Definition::Ancestor::Singleton.new(
                  name: absolute_type_name(super_class.name, namespace: namespace, location: location || decl.location)
                )
              end || Definition::Ancestor::Singleton.new(name: BuiltinNames::Object.name)

              build_ancestors(super_ancestor, ancestors: ancestors, building_ancestors: building_ancestors)
            end
          when AST::Declarations::Module
            module_ancestor = Definition::Ancestor::Instance.new(
              name: BuiltinNames::Module.name,
              args: []
            )
            build_ancestors module_ancestor, ancestors: ancestors, building_ancestors: building_ancestors
          end

          decl.members.each do |member|
            case member
            when AST::Members::Extend
              if member.name.class?
                ancestor = Definition::Ancestor::Instance.new(
                  name: absolute_type_name(member.name, namespace: namespace, location: member.location),
                  args: member.args.map {|ty| absolute_type(ty.sub(sub), namespace: namespace) }
                )
                build_ancestors ancestor, ancestors: ancestors, building_ancestors: building_ancestors, location: member.location
              end
            end
          end

          ancestors.unshift(self_ancestor)

          env.each_extension(self_ancestor.name).sort_by {|e| e.extension_name.to_s }.each do |extension|
            extension.members.each do |member|
              case member
              when AST::Members::Extend
                if member.name.class?
                  ancestor = Definition::Ancestor::Instance.new(
                    name: absolute_type_name(member.name, namespace: namespace, location: member.location),
                    args: member.args.map {|ty| absolute_type(ty, namespace: namespace) }
                  )
                  build_ancestors ancestor, ancestors: ancestors, building_ancestors: building_ancestors, location: member.location
                end
              end
            end

            extension_ancestor = Definition::Ancestor::ExtensionSingleton.new(
              name: extension.name.absolute!,
              extension_name: extension.extension_name
            )
            ancestors.unshift(extension_ancestor)
          end
        end

        building_ancestors.pop

        ancestors
      end

      def each_member_with_accessibility(members, accessibility: :public)
        members.each do |member|
          case member
          when AST::Members::Public
            accessibility = :public
          when AST::Members::Private
            accessibility = :private
          else
            yield member, accessibility
          end
        end
      end

      def build_instance(type_name)
        try_cache type_name, cache: instance_cache do
          decl = env.find_class(type_name)
          self_ancestor = Definition::Ancestor::Instance.new(name: type_name,
                                                             args: Types::Variable.build(decl.type_params.each.map(&:name)))
          self_type = Types::ClassInstance.new(name: type_name, args: self_ancestor.args, location: nil)

          case decl
          when AST::Declarations::Class, AST::Declarations::Module
            ancestors = build_ancestors(self_ancestor)
            definition_pairs = ancestors.map do |ancestor|
              case ancestor
              when Definition::Ancestor::Instance
                [ancestor, build_one_instance(ancestor.name)]
              when Definition::Ancestor::Singleton
                [ancestor, build_one_singleton(ancestor.name)]
              when Definition::Ancestor::ExtensionInstance
                [ancestor, build_one_instance(ancestor.name, extension_name: ancestor.extension_name)]
              when Definition::Ancestor::ExtensionSingleton
                [ancestor, build_one_extension_singleton(ancestor.name, extension_name: ancestor.extension_name)]
              end
            end

            if decl.is_a?(AST::Declarations::Module)
              if decl.self_type
                self_interface = absolute_type(decl.self_type, namespace: type_name.to_namespace)
                ancestor = Definition::Ancestor::Instance.new(name: self_interface.name,
                                                              args: self_interface.args)

                definition_pairs.push [ancestor, build_one_instance(ancestor.name)]
              end
            end

            merge_definitions(definition_pairs, decl: decl, self_type: self_type, ancestors: ancestors)
          end
        end
      end

      def build_singleton(type_name)
        try_cache type_name, cache: singleton_cache do
          decl = env.find_class(type_name)
          self_ancestor = Definition::Ancestor::Singleton.new(name: type_name)
          self_type = Types::ClassSingleton.new(name: type_name, location: nil)

          case decl
          when AST::Declarations::Class, AST::Declarations::Module
            ancestors = build_ancestors(self_ancestor)
            definition_pairs = ancestors.map do |ancestor|
              case ancestor
              when Definition::Ancestor::Instance
                [ancestor, build_one_instance(ancestor.name)]
              when Definition::Ancestor::Singleton
                [ancestor, build_one_singleton(ancestor.name)]
              when Definition::Ancestor::ExtensionInstance
                [ancestor, build_one_instance(ancestor.name, extension_name: ancestor.extension_name)]
              when Definition::Ancestor::ExtensionSingleton
                [ancestor, build_one_singleton(ancestor.name, extension_name: ancestor.extension_name)]
              end
            end

            if decl.is_a?(AST::Declarations::Class)
              definition_pairs.find {|ancestor, _| ancestor == self_ancestor }.tap do |_, definition|
                unless definition.methods[:new]&.implemented_in == decl
                  instance_definition = build_instance(type_name)
                  class_params = decl.type_params.each.map(&:name)
                  initialize_method = instance_definition.methods[:initialize]
                  method_types = initialize_method.method_types.map do |method_type|
                    case method_type
                    when MethodType
                      fvs = method_type.free_variables + class_params
                      unless fvs.empty?
                        param_name_set = Set.new(class_params)
                        bound_variables = method_type.type_params
                        renamed_types = bound_variables.map do |x|
                          if param_name_set.member?(x)
                            Types::Variable.fresh(x)
                          else
                            Types::Variable.new(name: x, location: nil)
                          end
                        end
                        sub = Substitution.build(bound_variables, renamed_types)
                        method_type_params = renamed_types.unshift(*class_params)
                      else
                        sub = Substitution.build([], [])
                        method_type_params = method_type.type_params
                      end

                      MethodType.new(
                        type_params: method_type_params,
                        type: method_type.type.sub(sub).with_return_type(instance_definition.self_type),
                        block: method_type.block&.yield_self {|ty| ty.sub(sub) },
                        location: method_type.location
                      )
                    end
                  end.compact

                  definition.methods[:new] = Definition::Method.new(
                    super_method: nil,
                    defined_in: nil,
                    implemented_in: env.find_class(Ruby::Signature::BuiltinNames::Class.name),
                    method_types: method_types,
                    accessibility: :public,
                    attributes: [:incompatible],
                    annotations: [],
                    comment: nil
                  )
                end
              end
            end

            merge_definitions(definition_pairs, decl: decl, self_type: self_type, ancestors: ancestors)
          end
        end
      end

      def build_one_instance(type_name, extension_name: nil)
        decl = if extension_name
                 env.each_extension(type_name).find {|ext| ext.extension_name == extension_name } or
                   raise "Unknown extension: #{type_name} (#{extension_name})"
               else
                 env.find_class(type_name)
               end

        case decl
        when AST::Declarations::Interface
          build_interface type_name, decl
        else
          namespace = type_name.to_namespace

          case decl
          when AST::Declarations::Class, AST::Declarations::Module
            self_type = Types::ClassInstance.new(name: type_name,
                                                 args: Types::Variable.build(decl.type_params.each.map(&:name)),
                                                 location: nil)
            ancestors = [Definition::Ancestor::Instance.new(name: type_name, args: self_type.args)]
          when AST::Declarations::Extension
            self_type = Types::ClassInstance.new(name: type_name, args: Types::Variable.build(decl.type_params), location: nil)
            ancestors = [Definition::Ancestor::ExtensionInstance.new(name: type_name,
                                                                     extension_name: extension_name,
                                                                     args: self_type.args)]
          end

          Definition.new(declaration: decl, self_type: self_type, ancestors: ancestors).tap do |definition|
            alias_members = []

            each_member_with_accessibility(decl.members) do |member, accessibility|
              case member
              when AST::Members::MethodDefinition
                if member.instance?
                  name = member.name
                  method_types = member.types.map do |method_type|
                    case method_type
                    when MethodType
                      method_type.map_type do |type|
                        absolute_type(type, namespace: namespace)
                      end
                    when :super
                      :super
                    end
                  end

                  DuplicatedMethodDefinitionError.check!(
                    decl: decl,
                    methods: definition.methods,
                    name: name,
                    location: member.location
                  )

                  attrs = if name == :initialize
                            (member.attributes + [:incompatible]).uniq
                          else
                            member.attributes
                          end

                  definition.methods[name] = Definition::Method.new(super_method: nil,
                                                                    method_types: method_types,
                                                                    defined_in: decl,
                                                                    implemented_in: decl,
                                                                    accessibility: accessibility,
                                                                    attributes: attrs,
                                                                    annotations: member.annotations,
                                                                    comment: member.comment)
                end
              when AST::Members::AttrReader, AST::Members::AttrAccessor, AST::Members::AttrWriter
                name = member.name
                type = absolute_type(member.type, namespace: namespace)
                ivar_name = case member.ivar_name
                            when false
                              nil
                            else
                              member.ivar_name || :"@#{member.name}"
                            end

                if member.is_a?(AST::Members::AttrReader) || member.is_a?(AST::Members::AttrAccessor)
                  definition.methods[name] = Definition::Method.new(
                    super_method: nil,
                    method_types: [
                      MethodType.new(
                        type_params: [],
                        type: Types::Function.empty(type),
                        block: nil,
                        location: nil
                      )
                    ],
                    defined_in: decl,
                    implemented_in: decl,
                    accessibility: accessibility,
                    attributes: [],
                    annotations: member.annotations,
                    comment: member.comment
                  )
                end

                if member.is_a?(AST::Members::AttrWriter) || member.is_a?(AST::Members::AttrAccessor)
                  definition.methods[:"#{name}="] = Definition::Method.new(
                    super_method: nil,
                    method_types: [
                      MethodType.new(
                        type_params: [],
                        type: Types::Function.new(required_positionals: [Types::Function::Param.new(name: name, type: type)],
                                                  optional_positionals: [],
                                                  rest_positionals: nil,
                                                  trailing_positionals: [],
                                                  required_keywords: {},
                                                  optional_keywords: {},
                                                  rest_keywords: nil,
                                                  return_type: type),
                        block: nil,
                        location: nil
                      )
                    ],
                    defined_in: decl,
                    implemented_in: decl,
                    accessibility: accessibility,
                    attributes: [],
                    annotations: member.annotations,
                    comment: member.comment
                  )
                end

                if ivar_name
                  definition.instance_variables[ivar_name] = Definition::Variable.new(
                    parent_variable: nil,
                    type: type,
                    declared_in: decl
                  )
                end

              when AST::Members::Alias
                if member.instance?
                  alias_members << member
                end
              when AST::Members::Include
                if member.name.interface?
                  absolute_name = absolute_type_name(member.name, namespace: namespace, location: member.location)
                  interface_definition = build_one_instance(absolute_name)
                  absolute_args = member.args.map {|ty| absolute_type(ty, namespace: namespace) }

                  InvalidTypeApplicationError.check!(
                    type_name: absolute_name,
                    args: absolute_args,
                    params: interface_definition.type_params_decl,
                    location: member.location
                  )

                  sub = Substitution.build(interface_definition.type_params, absolute_args)
                  interface_definition.methods.each do |name, method|
                    method_types = method.method_types.map do |method_type|
                      method_type.sub(sub).map_type do |type|
                        absolute_type(type, namespace: namespace)
                      end
                    end

                    DuplicatedMethodDefinitionError.check!(
                      decl: decl,
                      methods: definition.methods,
                      name: name,
                      location: member.location
                    )

                    definition.methods[name] = Definition::Method.new(
                      super_method: nil,
                      method_types: method_types,
                      defined_in: method.defined_in,
                      implemented_in: decl,
                      accessibility: method.accessibility,
                      attributes: [],
                      annotations: method.annotations,
                      comment: member.comment
                    )
                  end
                end
              when AST::Members::InstanceVariable
                definition.instance_variables[member.name] = Definition::Variable.new(
                  type: absolute_type(member.type, namespace: namespace),
                  parent_variable: nil,
                  declared_in: decl
                )
              when AST::Members::ClassVariable
                definition.class_variables[member.name] = Definition::Variable.new(
                  type: absolute_type(member.type, namespace: namespace),
                  parent_variable: nil,
                  declared_in: decl
                )
              end
            end

            alias_members.each do |member|
              UnknownMethodAliasError.check!(
                methods: definition.methods,
                original_name: member.old_name,
                aliased_name: member.new_name,
                location: member.location
              )

              DuplicatedMethodDefinitionError.check!(
                decl: decl,
                methods: definition.methods,
                name: member.new_name,
                location: member.location
              )

              # FIXME: may cause a problem if #old_name has super type
              definition.methods[member.new_name] = definition.methods[member.old_name]
            end

            validate_parameter_variance(
              decl: decl,
              methods: definition.methods
            )
          end
        end
      end

      def validate_params_with(type_params, result:)
        type_params.each do |param|
          unless param.skip_validation
            unless result.compatible?(param.name, with_annotation: param.variance)
              yield param
            end
          end
        end
      end

      def validate_parameter_variance(decl:, methods:)
        type_params = case decl
                      when AST::Declarations::Extension
                        env.find_class(decl.name.absolute!).type_params.rename_to(decl.type_params)
                      else
                        decl.type_params
                      end

        namespace = decl.name.absolute!.to_namespace
        calculator = VarianceCalculator.new(builder: self)
        param_names = type_params.each.map(&:name)

        errors = []

        if decl.is_a?(AST::Declarations::Class)
          if decl.super_class
            absolute_super_name = absolute_type_name(decl.super_class.name, namespace: namespace, location: decl.location)
            absolute_args = decl.super_class.args.map {|type| absolute_type(type, namespace: namespace) }
            result = calculator.in_inherit(name: absolute_super_name, args: absolute_args, variables: param_names)

            validate_params_with type_params, result: result do |param|
              errors.push InvalidVarianceAnnotationError::InheritanceError.new(
                param: param
              )
            end
          end
        end

        decl.members.each do |member|
          case member
          when AST::Members::Include
            if member.name.class?
              absolute_module_name = absolute_type_name(member.name, namespace: namespace, location: decl.location)
              absolute_args = member.args.map {|type| absolute_type(type, namespace: namespace) }
              result = calculator.in_inherit(name: absolute_module_name, args: absolute_args, variables: param_names)

              validate_params_with type_params, result: result do |param|
                errors.push InvalidVarianceAnnotationError::MixinError.new(
                  include_member: member,
                  param: param
                )
              end
            end
          end
        end

        methods.each do |name, method|
          method.method_types.each do |method_type|
            case method_type
            when MethodType
              result = calculator.in_method_type(method_type: method_type, variables: param_names)

              validate_params_with type_params, result: result do |param|
                errors.push InvalidVarianceAnnotationError::MethodTypeError.new(
                  method_name: name,
                  method_type: method_type,
                  param: param
                )
              end
            end
          end
        end

        unless errors.empty?
          raise InvalidVarianceAnnotationError.new(decl: decl, errors: errors)
        end
      end

      def build_one_singleton(type_name, extension_name: nil)
        decl = if extension_name
                 env.each_extension(type_name).find {|ext| ext.extension_name == extension_name } or
                   raise "Unknown extension: #{type_name} (#{extension_name})"
               else
                 env.find_class(type_name)
               end

        namespace = type_name.to_namespace

        case decl
        when AST::Declarations::Module, AST::Declarations::Class
          self_type = Types::ClassSingleton.new(name: type_name, location: nil)
          ancestors = [Definition::Ancestor::Singleton.new(name: type_name)]
        when AST::Declarations::Extension
          self_type = Types::ClassSingleton.new(name: type_name, location: nil)
          ancestors = [Definition::Ancestor::ExtensionSingleton.new(name: type_name, extension_name: extension_name)]
        end

        Definition.new(declaration: decl, self_type: self_type, ancestors: ancestors).tap do |definition|
          alias_members = []

          each_member_with_accessibility(decl.members) do |member, accessibility|
            case member
            when AST::Members::MethodDefinition
              if member.singleton?
                name = member.name
                method_types = member.types.map do |method_type|
                  method_type.map_type do |type|
                    absolute_type(type, namespace: namespace)
                  end
                end

                DuplicatedMethodDefinitionError.check!(
                  decl: decl,
                  methods: definition.methods,
                  name: name,
                  location: member.location
                )

                definition.methods[name] = Definition::Method.new(super_method: nil,
                                                                  method_types: method_types,
                                                                  defined_in: decl,
                                                                  implemented_in: decl,
                                                                  accessibility: accessibility,
                                                                  attributes: member.attributes,
                                                                  annotations: member.annotations,
                                                                  comment: member.comment)
              end
            when AST::Members::Alias
              if member.singleton?
                alias_members << member
              end
            when AST::Members::Extend
              if member.name.interface?
                absolute_name = absolute_type_name(member.name, namespace: namespace, location: member.location)
                interface_definition = build_one_instance(absolute_name)
                absolute_args = member.args.map {|ty| absolute_type(ty, namespace: namespace) }

                InvalidTypeApplicationError.check!(
                  type_name: absolute_name,
                  args: absolute_args,
                  params: interface_definition.type_params_decl,
                  location: member.location
                )

                sub = Substitution.build(interface_definition.type_params, absolute_args)
                interface_definition.methods.each do |name, method|
                  method_types = method.method_types.map do |method_type|
                    method_type.sub(sub).map_type do |type|
                      absolute_type(type, namespace: namespace)
                    end
                  end

                  DuplicatedMethodDefinitionError.check!(
                    decl: decl,
                    methods: definition.methods,
                    name: name,
                    location: member.location
                  )

                  definition.methods[name] = Definition::Method.new(
                    super_method: nil,
                    method_types: method_types,
                    defined_in: method.defined_in,
                    implemented_in: decl,
                    accessibility: method.accessibility,
                    attributes: method.attributes,
                    annotations: method.annotations,
                    comment: member.comment
                  )
                end
              end
            when AST::Members::ClassInstanceVariable
              definition.instance_variables[member.name] = Definition::Variable.new(
                type: absolute_type(member.type, namespace: namespace),
                parent_variable: nil,
                declared_in: decl
              )
            when AST::Members::ClassVariable
              definition.class_variables[member.name] = Definition::Variable.new(
                type: absolute_type(member.type, namespace: namespace),
                parent_variable: nil,
                declared_in: decl
              )
            end
          end

          alias_members.each do |member|
            UnknownMethodAliasError.check!(
              methods: definition.methods,
              original_name: member.old_name,
              aliased_name: member.new_name,
              location: member.location
            )

            DuplicatedMethodDefinitionError.check!(
              decl: decl,
              methods: definition.methods,
              name: member.new_name,
              location: member.location
            )

            # FIXME: may cause a problem if #old_name has super type
            definition.methods[member.new_name] = definition.methods[member.old_name]
          end
        end
      end

      def merge_definitions(pairs, decl:, self_type:, ancestors:)
        Definition.new(declaration: decl, self_type: self_type, ancestors: ancestors).tap do |definition|
          pairs.reverse_each do |(ancestor, current_definition)|
            sub = case ancestor
                  when Definition::Ancestor::Instance, Definition::Ancestor::ExtensionInstance
                    Substitution.build(current_definition.type_params, ancestor.args)
                  when Definition::Ancestor::Singleton, Definition::Ancestor::ExtensionSingleton
                    Substitution.build([], [])
                  end
            namespace = current_definition.name.absolute!.to_namespace

            current_definition.methods.each do |name, method|
              merge_method definition.methods, name, method, sub, namespace
            end

            current_definition.instance_variables.each do |name, variable|
              merge_variable definition.instance_variables, name, variable
            end

            current_definition.class_variables.each do |name, variable|
              merge_variable definition.class_variables, name, variable
            end
          end
        end
      end

      def merge_variable(variables, name, variable)
        super_variable = variables[name]

        variables[name] = Definition::Variable.new(
          parent_variable: super_variable,
          type: variable.type,
          declared_in: variable.declared_in
        )
      end

      def merge_method(methods, name, method, sub, namespace)
        super_method = methods[name]

        methods[name] = Definition::Method.new(
          method_types: method.method_types.flat_map do |method_type|
            case method_type
            when MethodType
              [absolute_type(method_type.sub(sub), namespace: namespace)]
            when :super
              super_method.method_types
            end
          end,
          super_method: super_method,
          defined_in: method.defined_in,
          implemented_in: method.implemented_in,
          accessibility: method.accessibility,
          attributes: method.attributes,
          annotations: method.annotations,
          comment: method.comment
        )
      end

      def try_cache(type_name, cache:)
        cached = cache[type_name]

        case cached
        when Definition
          cached
        when false
          raise
        when nil
          cache[type_name] = false
          begin
            cache[type_name] = yield
          rescue => ex
            cache[type_name] = nil
            raise ex
          end
        end
      end

      def build_interface(type_name, declaration = env.find_class(type_name))
        self_type = Types::Interface.new(
          name: type_name,
          args: declaration.type_params.each.map {|p| Types::Variable.new(name: p.name, location: nil) },
          location: nil
        )

        namespace = type_name.to_namespace

        Definition.new(declaration: declaration, self_type: self_type, ancestors: []).tap do |definition|
          alias_members = []

          declaration.members.each do |member|
            case member
            when AST::Members::Include
              mixin_name = env.absolute_interface_name(member.name, namespace: namespace) || member.name.absolute!
              mixin = build_one_instance(mixin_name)

              args = member.args.map {|type| absolute_type(type, namespace: namespace) }
              type_params = mixin.declaration.type_params

              InvalidTypeApplicationError.check!(
                type_name: type_name,
                args: args,
                params: type_params,
                location: member.location
              )

              sub = Substitution.build(type_params.each.map(&:name), args)
              mixin.methods.each do |name, method|
                definition.methods[name] = method.sub(sub)
              end
            end
          end

          declaration.members.each do |member|
            case member
            when AST::Members::MethodDefinition
              DuplicatedMethodDefinitionError.check!(
                decl: declaration,
                methods: definition.methods,
                name: member.name,
                location: member.location
              )

              method = Definition::Method.new(
                super_method: nil,
                method_types: member.types.map do |method_type|
                  method_type.map_type {|ty| absolute_type(ty, namespace: namespace) }
                end,
                defined_in: declaration,
                implemented_in: nil,
                accessibility: :public,
                attributes: member.attributes,
                annotations: member.annotations,
                comment: member.comment
              )
              definition.methods[member.name] = method
            when AST::Members::Alias
              alias_members << member
            end
          end

          alias_members.each do |member|
            UnknownMethodAliasError.check!(
              methods: definition.methods,
              original_name: member.old_name,
              aliased_name: member.new_name,
              location: member.location
            )

            DuplicatedMethodDefinitionError.check!(
              decl: declaration,
              methods: definition.methods,
              name: member.new_name,
              location: member.location
            )

            # FIXME: may cause a problem if #old_name has super type
            definition.methods[member.new_name] = definition.methods[member.old_name]
          end
        end
      end

      def absolute_type(type, namespace:)
        env.absolute_type(type, namespace: namespace) do |type|
          NoTypeFoundError.check!(type.name.absolute!, env: env, location: type.location)
        end
      end

      def absolute_type_name(type_name, namespace:, location:)
        env.absolute_type_name(type_name, namespace: namespace) do |type_name|
          NoTypeFoundError.check!(type_name.absolute!, env: env, location: location)
        end
      end

      def expand_alias(type_name)
        absolute_type(env.find_alias(type_name).type, namespace: type_name.namespace)
      end
    end
  end
end
