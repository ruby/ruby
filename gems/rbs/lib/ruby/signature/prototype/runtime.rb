module Ruby
  module Signature
    module Prototype
      class Runtime
        attr_reader :patterns
        attr_reader :env
        attr_reader :merge
        attr_reader :owners_included

        def initialize(patterns:, env:, merge:, owners_included: [])
          @patterns = patterns
          @decls = nil
          @env = env
          @merge = merge
          @owners_included = owners_included.map do |name|
            Object.const_get(name)
          end
        end

        def target?(const)
          patterns.any? do |pattern|
            if pattern.end_with?("*")
              (const.name || "").start_with?(pattern.chop)
            else
              const.name == pattern
            end
          end
        end

        def builder
          @builder ||= DefinitionBuilder.new(env: env)
        end

        def parse(file)
          require file
        end

        def decls
          unless @decls
            @decls = []
            ObjectSpace.each_object(Module).select {|mod| target?(mod) }.sort_by(&:name).each do |mod|
              case mod
              when Class
                generate_class mod
              when Module
                generate_module mod
              end
            end
          end
          @decls
        end

        def to_type_name(name)
          *prefix, last = name.split(/::/)

          if prefix.empty?
            TypeName.new(name: last.to_sym, namespace: Namespace.empty)
          else
            TypeName.new(name: last.to_sym, namespace: Namespace.parse(prefix.join("::")))
          end
        end

        def each_mixin(mixins, *super_mixes)
          supers = Set.new(super_mixes)
          mixins.each do |mix|
            unless supers.include?(mix)
              yield mix
            end
          end
        end

        def method_type(method)
          untyped = Types::Bases::Any.new(location: nil)

          required_positionals = []
          optional_positionals = []
          rest = nil
          trailing_positionals = []
          required_keywords = {}
          optional_keywords = {}
          rest_keywords = nil

          requireds = required_positionals

          block = nil

          method.parameters.each do |kind, name|
            case kind
            when :req
              requireds << Types::Function::Param.new(name: name, type: untyped)
            when :opt
              requireds = trailing_positionals
              optional_positionals << Types::Function::Param.new(name: name, type: untyped)
            when :rest
              requireds = trailing_positionals
              rest = Types::Function::Param.new(name: name, type: untyped)
            when :keyreq
              required_keywords[name] = Types::Function::Param.new(name: nil, type: untyped)
            when :key
              optional_keywords[name] = Types::Function::Param.new(name: nil, type: untyped)
            when :keyrest
              rest_keywords = Types::Function::Param.new(name: nil, type: untyped)
            when :block
              block = MethodType::Block.new(
                type: Types::Function.empty(untyped).update(rest_positionals: Types::Function::Param.new(name: nil, type: untyped)),
                required: true
              )
            end
          end

          method_type = Types::Function.new(
            required_positionals: required_positionals,
            optional_positionals: optional_positionals,
            rest_positionals: rest,
            trailing_positionals: trailing_positionals,
            required_keywords: required_keywords,
            optional_keywords: optional_keywords,
            rest_keywords: rest_keywords,
            return_type: untyped
          )

          MethodType.new(
            location: nil,
            type_params: [],
            type: method_type,
            block: block
          )
        end

        def merge_rbs(module_name, members, instance: nil, singleton: nil)
          if merge
            if env.class?(module_name.absolute!)
              case
              when instance
                method = builder.build_instance(module_name.absolute!).methods[instance]
                method_name = instance
                kind = :instance
              when singleton
                method = builder.build_singleton(module_name.absolute!).methods[singleton]
                method_name = singleton
                kind = :singleton
              end

              if method
                members << AST::Members::MethodDefinition.new(
                  name: method_name,
                  types: method.method_types.map {|type|
                    type.update.tap do |ty|
                      def ty.to_s
                        location.source
                      end
                    end
                  },
                  kind: kind,
                  location: nil,
                  comment: method.comment,
                  annotations: method.annotations,
                  attributes: method.attributes
                )
                return
              end
            end

            yield
          else
            yield
          end
        end

        def target_method?(mod, instance: nil, singleton: nil)
          case
          when instance
            method = mod.instance_method(instance)
            method.owner == mod || owners_included.any? {|m| method.owner == m }
          when singleton
            method = mod.singleton_class.instance_method(singleton)
            method.owner == mod.singleton_class || owners_included.any? {|m| method.owner == m.singleton_class }
          end
        end

        def generate_methods(mod, module_name, members)
          mod.singleton_methods.select {|name| target_method?(mod, singleton: name) }.sort.each do |name|
            method = mod.singleton_class.instance_method(name)

            if method.name == method.original_name
              merge_rbs(module_name, members, singleton: name) do
                Signature.logger.info "missing #{module_name}.#{name} #{method.source_location}"
                
                members << AST::Members::MethodDefinition.new(
                  name: method.name,
                  types: [method_type(method)],
                  kind: :singleton,
                  location: nil,
                  comment: nil,
                  annotations: [],
                  attributes: []
                )
              end
            else
              members << AST::Members::Alias.new(
                new_name: method.name,
                old_name: method.original_name,
                kind: :singleton,
                location: nil,
                comment: nil,
                annotations: [],
                )
            end
          end

          public_instance_methods = mod.public_instance_methods.select {|name| target_method?(mod, instance: name) }
          unless public_instance_methods.empty?
            members << AST::Members::Public.new(location: nil)

            public_instance_methods.sort.each do |name|
              method = mod.instance_method(name)

              if method.name == method.original_name
                merge_rbs(module_name, members, instance: name) do
                  Signature.logger.info "missing #{module_name}##{name} #{method.source_location}"

                  members << AST::Members::MethodDefinition.new(
                    name: method.name,
                    types: [method_type(method)],
                    kind: :instance,
                    location: nil,
                    comment: nil,
                    annotations: [],
                    attributes: []
                  )
                end
              else
                members << AST::Members::Alias.new(
                  new_name: method.name,
                  old_name: method.original_name,
                  kind: :instance,
                  location: nil,
                  comment: nil,
                  annotations: [],
                  )
              end
            end
          end

          private_instance_methods = mod.private_instance_methods.select {|name| target_method?(mod, instance: name) }
          unless private_instance_methods.empty?
            members << AST::Members::Private.new(location: nil)

            private_instance_methods.sort.each do |name|
              method = mod.instance_method(name)

              if method.name == method.original_name
                merge_rbs(module_name, members, instance: name) do
                  Signature.logger.info "missing #{module_name}##{name} #{method.source_location}"

                  members << AST::Members::MethodDefinition.new(
                    name: method.name,
                    types: [method_type(method)],
                    kind: :instance,
                    location: nil,
                    comment: nil,
                    annotations: [],
                    attributes: []
                  )
                end
              else
                members << AST::Members::Alias.new(
                  new_name: method.name,
                  old_name: method.original_name,
                  kind: :instance,
                  location: nil,
                  comment: nil,
                  annotations: [],
                  )
              end
            end
          end
        end

        def generate_constants(mod)
          mod.constants(false).sort.each do |name|
            value = mod.const_get(name)

            next if value.is_a?(Class) || value.is_a?(Module)
            type = case value
                   when true, false
                     Types::Bases::Bool.new(location: nil)
                   when nil
                     Types::Optional.new(
                       type: Types::Bases::Any.new(location: nil),
                       location: nil
                     )
                   else
                     Types::ClassInstance.new(name: to_type_name(value.class.to_s), args: [], location: nil)
                   end

            @decls << AST::Declarations::Constant.new(
              name: "#{mod.to_s}::#{name}",
              type: type,
              location: nil,
              comment: nil
            )
          end
        end

        def generate_class(mod)
          type_name = to_type_name(mod.name)
          super_class = if mod.superclass == ::Object
                          nil
                        else
                          AST::Declarations::Class::Super.new(name: to_type_name(mod.superclass.name), args: [])
                        end

          decl = AST::Declarations::Class.new(
            name: type_name,
            type_params: AST::Declarations::ModuleTypeParams.empty,
            super_class: super_class,
            members: [],
            annotations: [],
            location: nil,
            comment: nil
          )

          each_mixin(mod.included_modules, *mod.superclass.included_modules, *mod.included_modules.flat_map(&:included_modules)) do |included_module|
            module_name = to_type_name(included_module.name)
            if module_name.namespace == type_name.namespace
              module_name = TypeName.new(name: module_name.name, namespace: Namespace.empty)
            end

            decl.members << AST::Members::Include.new(
              name: module_name,
              args: [],
              location: nil,
              comment: nil,
              annotations: []
            )
          end

          generate_methods(mod, type_name, decl.members)

          @decls << decl

          generate_constants mod
        end

        def generate_module(mod)
          type_name = to_type_name(mod.name)

          decl = AST::Declarations::Module.new(
            name: type_name,
            type_params: AST::Declarations::ModuleTypeParams.empty,
            self_type: nil,
            members: [],
            annotations: [],
            location: nil,
            comment: nil
          )

          each_mixin(mod.included_modules, *mod.included_modules.flat_map(&:included_modules), namespace: type_name.namespace) do |included_module|
            module_name = to_type_name(included_module.name)
            if module_name.namespace == type_name.namespace
              module_name = TypeName.new(name: module_name.name, namespace: Namespace.empty)
            end

            decl.members << AST::Members::Include.new(
              name: module_name,
              args: [],
              location: nil,
              comment: nil,
              annotations: []
            )
          end

          generate_methods(mod, type_name, decl.members)

          @decls << decl

          generate_constants mod
        end
      end
    end
  end
end
