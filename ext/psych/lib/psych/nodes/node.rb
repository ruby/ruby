require 'stringio'

module Psych
  module Nodes
    ###
    # The base class for any Node in a YAML parse tree.  This class should
    # never be instantiated.
    class Node
      # The children of this node
      attr_reader :children

      # An associated tag
      attr_reader :tag

      # Create a new Psych::Nodes::Node
      def initialize
        @children = []
      end

      ###
      # Convert this node to Ruby.
      #
      # See also Psych::Visitors::ToRuby
      def to_ruby
        Visitors::ToRuby.new.accept self
      end
      alias :transform :to_ruby

      ###
      # Convert this node to YAML.
      #
      # See also Psych::Visitors::Emitter
      def to_yaml io = nil
        real_io = io || StringIO.new

        Visitors::Emitter.new(real_io).accept self
        return real_io.string unless io
        io
      end
    end
  end
end
