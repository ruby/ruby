require 'psych/handler'

module Psych
  ###
  # This class works in conjunction with Psych::Parser to build an in-memory
  # parse tree that represents a YAML document.
  #
  # == Example
  #
  #   parser = Psych::Parser.new Psych::TreeBuilder.new
  #   parser.parse('--- foo')
  #   tree = parser.handler.root
  #
  # See Psych::Handler for documentation on the event methods used in this
  # class.
  class TreeBuilder < Psych::Handler
    # Create a new TreeBuilder instance
    def initialize
      @stack = []
      @last  = nil
    end

    # Returns the root node for the built tree
    def root
      @stack.first
    end

    %w{
      Sequence
      Mapping
    }.each do |node|
      class_eval %{
        def start_#{node.downcase}(anchor, tag, implicit, style)
          n = Nodes::#{node}.new(anchor, tag, implicit, style)
          @last.children << n
          push n
        end

        def end_#{node.downcase}
          pop
        end
      }
    end

    ###
    # Handles start_document events with +version+, +tag_directives+,
    # and +implicit+ styling.
    #
    # See Psych::Handler#start_document
    def start_document version, tag_directives, implicit
      n = Nodes::Document.new(version, tag_directives, implicit)
      @last.children << n
      push n
    end

    ###
    # Handles end_document events with +version+, +tag_directives+,
    # and +implicit+ styling.
    #
    # See Psych::Handler#start_document
    def end_document implicit_end
      @last.implicit_end = implicit_end
      pop
    end

    def start_stream encoding
      push Nodes::Stream.new(encoding)
    end

    def scalar value, anchor, tag, plain, quoted, style
      @last.children << Nodes::Scalar.new(value,anchor,tag,plain,quoted,style)
    end

    def alias anchor
      @last.children << Nodes::Alias.new(anchor)
    end

    private
    def push value
      @stack.push value
      @last = value
    end

    def pop
      @stack.pop
      @last = @stack.last
    end
  end
end
