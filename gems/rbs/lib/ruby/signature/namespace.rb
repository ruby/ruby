module Ruby
  module Signature
    class Namespace
      attr_reader :path

      def initialize(path:, absolute:)
        @path = path
        @absolute = absolute
      end

      def self.empty
        new(path: [], absolute: false)
      end

      def self.root
        new(path: [], absolute: true)
      end

      def +(other)
        if other.absolute?
          other
        else
          self.class.new(path: path + other.path, absolute: absolute?)
        end
      end

      def append(component)
        self.class.new(path: path + [component], absolute: absolute?)
      end

      def parent
        raise "Parent with empty namespace" if empty?
        self.class.new(path: path.take(path.size - 1), absolute: absolute?)
      end

      def absolute?
        @absolute
      end

      def relative?
        !absolute?
      end

      def absolute!
        self.class.new(path: path, absolute: true)
      end

      def relative!
        self.class.new(path: path, absolute: false)
      end

      def empty?
        path.empty?
      end

      def ==(other)
        other.is_a?(Namespace) && other.path == path && other.absolute? == absolute?
      end

      alias eql? ==

      def hash
        self.class.hash ^ path.hash ^ absolute?.hash
      end

      def split
        [parent, path.last]
      end

      def to_s
        if empty?
          absolute? ? "::" : ""
        else
          s = path.join("::")
          absolute? ? "::#{s}::" : "#{s}::"
        end
      end

      def to_type_name
        parent, name = split
        TypeName.new(name: name, namespace: parent)
      end

      def self.parse(string)
        if string.start_with?("::")
          new(path: string.split("::").drop(1).map(&:to_sym), absolute: true)
        else
          new(path: string.split("::").map(&:to_sym), absolute: false)
        end
      end
    end
  end
end
