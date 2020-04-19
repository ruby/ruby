module Ruby
  module Signature
    class Environment
      attr_reader :buffers
      attr_reader :declarations

      attr_reader :name_to_decl
      attr_reader :name_to_extensions
      attr_reader :name_to_constant
      attr_reader :name_to_global
      attr_reader :name_to_alias

      def initialize
        @buffers = []
        @declarations = []

        @name_to_decl = {}
        @name_to_extensions = {}
        @name_to_constant = {}
        @name_to_global = {}
        @name_to_alias = {}
      end

      def initialize_copy(other)
        @buffers = other.buffers.dup
        @declarations = other.declarations.dup

        @name_to_decl = other.name_to_decl.dup
        @name_to_extensions = other.name_to_extensions.dup
        @name_to_constant = other.name_to_constant.dup
        @name_to_global = other.name_to_global.dup
        @name_to_alias = other.name_to_alias.dup
      end

      def cache_name(cache, name:, decl:)
        if cache.key?(name)
          raise DuplicatedDeclarationError.new(name, decl, cache[name])
        end
        cache[name] = decl
      end

      def <<(decl)
        declarations << decl
        case decl
        when AST::Declarations::Class, AST::Declarations::Module, AST::Declarations::Interface
          cache_name name_to_decl, name: decl.name.absolute!, decl: decl
        when AST::Declarations::Extension
          yield_self do
            name = decl.name.absolute!
            exts = name_to_extensions.fetch(name) do
              name_to_extensions[name] = []
            end
            exts << decl
          end
        when AST::Declarations::Alias
          cache_name name_to_alias, name: decl.name.absolute!, decl: decl
        when AST::Declarations::Constant
          cache_name name_to_constant, name: decl.name.absolute!, decl: decl
        when AST::Declarations::Global
          cache_name name_to_global, name: decl.name, decl: decl
        end
      end

      def find_class(type_name)
        name_to_decl[type_name]
      end

      def each_decl
        if block_given?
          name_to_decl.each do |name, decl|
            yield name, decl
          end
        else
          enum_for :each_decl
        end
      end

      def each_constant
        if block_given?
          name_to_constant.each do |name, decl|
            yield name, decl
          end
        else
          enum_for :each_constant
        end
      end

      def each_global
        if block_given?
          name_to_global.each do |name, global|
            yield name, global
          end
        else
          enum_for :each_global
        end
      end

      def each_alias(&block)
        if block_given?
          name_to_alias.each(&block)
        else
          enum_for :each_alias
        end
      end

      def each_class_name(&block)
        each_decl.select {|name,| class?(name) }.each(&block)
      end

      def class?(type_name)
        find_class(type_name)&.yield_self do |decl|
          decl.is_a?(AST::Declarations::Class) || decl.is_a?(AST::Declarations::Module)
        end
      end

      def find_type_decl(type_name)
        name_to_decl[type_name]
      end

      def find_extensions(type_name)
        name_to_extensions[type_name] || []
      end

      def find_alias(type_name)
        name_to_alias[type_name]
      end

      def each_extension(type_name, &block)
        if block_given?
          (name_to_extensions[type_name] || []).each(&block)
        else
          enum_for :each_extension, type_name
        end
      end

      def absolute_type_name_in(environment, name:, namespace:)
        raise "Namespace should be absolute: #{namespace}" unless namespace.absolute?

        if name.absolute?
          name if environment.key?(name)
        else
          absolute_name = name.with_prefix(namespace)

          if environment.key?(absolute_name)
            absolute_name
          else
            if namespace.empty?
              nil
            else
              parent = namespace.parent
              absolute_type_name_in environment, name: name, namespace: parent
            end
          end
        end
      end

      def absolute_class_name(name, namespace:)
        raise "Class name expected: #{name}" unless name.class?
        absolute_type_name_in name_to_decl, name: name, namespace: namespace
      end

      def absolute_interface_name(name, namespace:)
        raise "Interface name expected: #{name}" unless name.interface?
        absolute_type_name_in name_to_decl, name: name, namespace: namespace
      end

      def absolute_alias_name(name, namespace:)
        raise "Alias name expected: #{name}" unless name.alias?
        absolute_type_name_in name_to_alias, name: name, namespace: namespace
      end

      def absolute_type_name(type_name, namespace:)
        absolute_name = case
                        when type_name.class?
                          absolute_class_name(type_name, namespace: namespace)
                        when type_name.alias?
                          absolute_alias_name(type_name, namespace: namespace)
                        when type_name.interface?
                          absolute_interface_name(type_name, namespace: namespace)
                        end

        absolute_name || yield(type_name)
      end

      def absolute_name_or(name, type)
        if name.absolute?
          type
        else
          yield
        end
      end

      def absolute_type(type, namespace:, &block)
        case type
        when Types::ClassSingleton
          absolute_name_or(type.name, type) do
            absolute_name = absolute_type_name(type.name, namespace: namespace) { yield(type) }
            Types::ClassSingleton.new(name: absolute_name, location: type.location)
          end
        when Types::ClassInstance
          absolute_name = absolute_type_name(type.name, namespace: namespace) { yield(type) }
          Types::ClassInstance.new(name: absolute_name,
                                   args: type.args.map {|ty|
                                     absolute_type(ty, namespace: namespace, &block)
                                   },
                                   location: type.location)
        when Types::Interface
          absolute_name = absolute_type_name(type.name, namespace: namespace) { yield(type) }
          Types::Interface.new(name: absolute_name,
                               args: type.args.map {|ty|
                                 absolute_type(ty, namespace: namespace, &block)
                               },
                               location: type.location)
        when Types::Alias
          absolute_name_or(type.name, type) do
            absolute_name = absolute_type_name(type.name, namespace: namespace) { yield(type) }
            Types::Alias.new(name: absolute_name, location: type.location)
          end
        when Types::Tuple
          Types::Tuple.new(
            types: type.types.map {|ty| absolute_type(ty, namespace: namespace, &block) },
            location: type.location
          )
        when Types::Record
          Types::Record.new(
            fields: type.fields.transform_values {|ty| absolute_type(ty, namespace: namespace, &block) },
            location: type.location
          )
        when Types::Union
          Types::Union.new(
            types: type.types.map {|ty| absolute_type(ty, namespace: namespace, &block) },
            location: type.location
          )
        when Types::Intersection
          Types::Intersection.new(
            types: type.types.map {|ty| absolute_type(ty, namespace: namespace, &block) },
            location: type.location
          )
        when Types::Optional
          Types::Optional.new(
            type: absolute_type(type.type, namespace: namespace, &block),
            location: type.location
          )
        when Types::Proc
          Types::Proc.new(
            type: type.type.map_type {|ty| absolute_type(ty, namespace: namespace, &block) },
            location: type.location
          )
        else
          type
        end
      end

      # Validates presence of the relative type, and application arity match.
      def validate(type, namespace:)
        case type
        when Types::ClassInstance, Types::Interface
          if type.name.namespace.relative?
            type = absolute_type(type, namespace: namespace) do |type|
              NoTypeFoundError.check!(type.name.absolute!, env: self, location: type.location)
            end
          end

          decl = find_class(type.name)
          unless decl
            raise NoTypeFoundError.new(type_name: type.name, location: type.location)
          end

          InvalidTypeApplicationError.check!(
            type_name: type.name,
            args: type.args,
            params: decl.type_params,
            location: type.location
          )
        end

        type.each_type do |type_|
          validate(type_, namespace: namespace)
        end
      end
    end
  end
end
