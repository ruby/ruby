module Ruby
  module Signature
    class Constant
      attr_reader :name
      attr_reader :type
      attr_reader :declaration

      def initialize(name:, type:, declaration:)
        @name = name
        @type = type
        @declaration = declaration
      end

      def ==(other)
        other.is_a?(Constant) &&
          other.name == name &&
          other.type == type &&
          other.declaration == declaration
      end

      alias eql? ==

      def hash
        self.class.hash ^ name.hash ^ type.hash ^ declaration.hash
      end
    end
  end
end
