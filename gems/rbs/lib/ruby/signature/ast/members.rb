module Ruby
  module Signature
    module AST
      module Members
        class MethodDefinition
          attr_reader :name
          attr_reader :kind
          attr_reader :types
          attr_reader :annotations
          attr_reader :location
          attr_reader :comment
          attr_reader :attributes

          def initialize(name:, kind:, types:, annotations:, location:, comment:, attributes:)
            @name = name
            @kind = kind
            @types = types
            @annotations = annotations
            @location = location
            @comment = comment
            @attributes = attributes
          end

          def ==(other)
            other.is_a?(MethodDefinition) &&
              other.name == name &&
              other.kind == kind &&
              other.types == types &&
              other.attributes == attributes
          end

          alias eql? ==

          def hash
            self.class.hash ^ name.hash ^ kind.hash ^ types.hash ^ attributes.hash
          end

          def instance?
            kind == :instance || kind == :singleton_instance
          end

          def singleton?
            kind == :singleton || kind == :singleton_instance
          end

          def to_json(*a)
            {
              member: :method_definition,
              kind: kind,
              types: types,
              annotations: annotations,
              location: location,
              comment: comment,
              attributes: attributes
            }.to_json(*a)
          end
        end

        module Var
          attr_reader :name
          attr_reader :type
          attr_reader :location
          attr_reader :comment

          def initialize(name:, type:, location:, comment:)
            @name = name
            @type = type
            @location = location
            @comment = comment
          end

          def ==(other)
            other.is_a?(self.class) && other.name == name && other.type == type
          end

          alias eql? ==

          def hash
            self.class.hash ^ name.hash ^ type.hash
          end
        end

        class InstanceVariable
          include Var

          def to_json(*a)
            {
              member: :instance_variable,
              name: name,
              type: type,
              location: location,
              comment: comment
            }.to_json(*a)
          end
        end

        class ClassInstanceVariable
          include Var

          def to_json(*a)
            {
              member: :class_instance_variable,
              name: name,
              type: type,
              location: location,
              comment: comment
            }.to_json(*a)
          end
        end

        class ClassVariable
          include Var

          def to_json(*a)
            {
              member: :class_variable,
              name: name,
              type: type,
              location: location,
              comment: comment
            }.to_json(*a)
          end
        end

        module Mixin
          attr_reader :name
          attr_reader :args
          attr_reader :annotations
          attr_reader :location
          attr_reader :comment

          def initialize(name:, args:, annotations:, location:, comment:)
            @name = name
            @args = args
            @annotations = annotations
            @location = location
            @comment = comment
          end

          def ==(other)
            other.is_a?(self.class) && other.name == name && other.args == args
          end

          def eql?(other)
            self == other
          end

          def hash
            self.class.hash ^ name.hash ^ args.hash
          end
        end

        class Include
          include Mixin

          def to_json(*a)
            {
              member: :include,
              name: name,
              args: args,
              annotations: annotations,
              location: location,
              comment: comment
            }.to_json(*a)
          end
        end

        class Extend
          include Mixin

          def to_json(*a)
            {
              member: :extend,
              name: name,
              args: args,
              annotations: annotations,
              location: location,
              comment: comment
            }.to_json(*a)
          end
        end

        class Prepend
          include Mixin

          def to_json(*a)
            {
              member: :prepend,
              name: name,
              args: args,
              annotations: annotations,
              location: location,
              comment: comment
            }.to_json(*a)
          end
        end

        module Attribute
          attr_reader :name
          attr_reader :type
          attr_reader :ivar_name
          attr_reader :annotations
          attr_reader :location
          attr_reader :comment

          def initialize(name:, type:, ivar_name:, annotations:, location:, comment:)
            @name = name
            @type = type
            @ivar_name = ivar_name
            @annotations = annotations
            @location = location
            @comment = comment
          end

          def ==(other)
            other.is_a?(self.class) &&
              other.name == name &&
              other.type == type &&
              other.ivar_name == ivar_name
          end

          alias eql? ==

          def hash
            self.class.hash ^ name.hash ^ type.hash ^ ivar_name.hash
          end
        end

        class AttrReader
          include Attribute

          def to_json(*a)
            {
              member: :attr_reader,
              name: name,
              type: type,
              ivar_name: ivar_name,
              annotations: annotations,
              location: location,
              comment: comment
            }.to_json(*a)
          end
        end

        class AttrAccessor
          include Attribute

          def to_json(*a)
            {
              member: :attr_accessor,
              name: name,
              type: type,
              ivar_name: ivar_name,
              annotations: annotations,
              location: location,
              comment: comment
            }.to_json(*a)
          end
        end

        class AttrWriter
          include Attribute

          def to_json(*a)
            {
              member: :attr_writer,
              name: name,
              type: type,
              ivar_name: ivar_name,
              annotations: annotations,
              location: location,
              comment: comment
            }.to_json(*a)
          end
        end

        module LocationOnly
          attr_reader :location

          def initialize(location:)
            @location = location
          end

          def ==(other)
            other.is_a?(self.class)
          end

          alias eql? ==

          def hash
            self.class.hash
          end
        end

        class Public
          include LocationOnly

          def to_json(*a)
            { member: :public, location: location }.to_json(*a)
          end
        end

        class Private
          include LocationOnly

          def to_json(*a)
            { member: :private, location: location }.to_json(*a)
          end
        end

        class Alias
          attr_reader :new_name
          attr_reader :old_name
          attr_reader :kind
          attr_reader :annotations
          attr_reader :location
          attr_reader :comment

          def initialize(new_name:, old_name:, kind:, annotations:, location:, comment:)
            @new_name = new_name
            @old_name = old_name
            @kind = kind
            @annotations = annotations
            @location = location
            @comment = comment
          end

          def ==(other)
            other.is_a?(self.class) &&
              other.new_name == new_name &&
              other.old_name == old_name &&
              other.kind == kind
          end

          alias eql? ==

          def hash
            self.class.hash ^ new_name.hash ^ old_name.hash ^ kind.hash
          end

          def to_json(*a)
            {
              member: :alias,
              new_name: new_name,
              old_name: old_name,
              kind: kind,
              annotations: annotations,
              location: location,
              comment: comment
            }.to_json(*a)
          end

          def instance?
            kind == :instance
          end

          def singleton?
            kind == :singleton
          end
        end
      end
    end
  end
end
