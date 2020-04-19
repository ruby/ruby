module Ruby
  module Signature
    class Definition
      class Variable
        attr_reader :parent_variable
        attr_reader :type
        attr_reader :declared_in

        def initialize(parent_variable:, type:, declared_in:)
          @parent_variable = parent_variable
          @type = type
          @declared_in = declared_in
        end
      end

      class Method
        attr_reader :super_method
        attr_reader :method_types
        attr_reader :defined_in
        attr_reader :implemented_in
        attr_reader :accessibility
        attr_reader :attributes
        attr_reader :annotations
        attr_reader :comment

        def initialize(super_method:, method_types:, defined_in:, implemented_in:, accessibility:, attributes:, annotations:, comment:)
          @super_method = super_method
          @method_types = method_types
          @defined_in = defined_in
          @implemented_in = implemented_in
          @accessibility = accessibility
          @attributes = attributes
          @annotations = annotations
          @comment = comment
        end

        def public?
          @accessibility == :public
        end

        def private?
          @accessibility == :private
        end

        def sub(s)
          self.class.new(
            super_method: super_method&.sub(s),
            method_types: method_types.map {|ty| ty.sub(s) },
            defined_in: defined_in,
            implemented_in: implemented_in,
            accessibility: @accessibility,
            attributes: attributes,
            annotations: annotations,
            comment: comment
          )
        end

        def map_type(&block)
          self.class.new(
            super_method: super_method&.map_type(&block),
            method_types: method_types.map do |ty|
              ty.map_type(&block)
            end,
            defined_in: defined_in,
            implemented_in: implemented_in,
            accessibility: @accessibility,
            attributes: attributes,
            annotations: annotations,
            comment: comment
          )
        end
      end

      module Ancestor
        Instance = Struct.new(:name, :args, keyword_init: true)
        Singleton = Struct.new(:name, keyword_init: true)
        ExtensionInstance = Struct.new(:name, :extension_name, :args, keyword_init: true)
        ExtensionSingleton = Struct.new(:name, :extension_name, keyword_init: true)
      end

      attr_reader :declaration
      attr_reader :self_type
      attr_reader :methods
      attr_reader :instance_variables
      attr_reader :class_variables
      attr_reader :ancestors

      def initialize(declaration:, self_type:, ancestors:)
        unless declaration.is_a?(AST::Declarations::Class) ||
          declaration.is_a?(AST::Declarations::Module) ||
          declaration.is_a?(AST::Declarations::Interface) ||
          declaration.is_a?(AST::Declarations::Extension)
          raise "Declaration should be a class, module, or interface: #{declaration.name}"
        end

        unless (self_type.is_a?(Types::ClassSingleton) || self_type.is_a?(Types::Interface) || self_type.is_a?(Types::ClassInstance)) && self_type.name == declaration.name.absolute!
          raise "self_type should be the type of declaration: #{self_type}"
        end

        @self_type = self_type
        @declaration = declaration
        @methods = {}
        @instance_variables = {}
        @class_variables = {}
        @ancestors = ancestors
      end

      def name
        declaration.name
      end

      def class?
        declaration.is_a?(AST::Declarations::Class)
      end

      def module?
        declaration.is_a?(AST::Declarations::Module)
      end

      def class_type?
        @self_type.is_a?(Types::ClassSingleton)
      end

      def instance_type?
        @self_type.is_a?(Types::ClassInstance)
      end

      def interface_type?
        @self_type.is_a?(Types::Interface)
      end

      def type_params
        @self_type.args.map(&:name)
      end

      def type_params_decl
        case declaration
        when AST::Declarations::Extension
          nil
        else
          declaration.type_params
        end
      end

      def each_type(&block)
        if block_given?
          methods.each_value do |method|
            if method.defined_in == self.declaration
              method.method_types.each do |method_type|
                method_type.each_type(&block)
              end
            end
          end

          instance_variables.each_value do |var|
            if var.declared_in == self.declaration
              yield var.type
            end
          end

          class_variables.each_value do |var|
            if var.declared_in == self.declaration
              yield var.type
            end
          end
        else
          enum_for :each_type
        end
      end
    end
  end
end
