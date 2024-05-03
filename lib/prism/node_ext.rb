# frozen_string_literal: true

# Here we are reopening the prism module to provide methods on nodes that aren't
# templated and are meant as convenience methods.
module Prism
  module RegularExpressionOptions # :nodoc:
    # Returns a numeric value that represents the flags that were used to create
    # the regular expression.
    def options
      o = flags & (RegularExpressionFlags::IGNORE_CASE | RegularExpressionFlags::EXTENDED | RegularExpressionFlags::MULTI_LINE)
      o |= Regexp::FIXEDENCODING if flags.anybits?(RegularExpressionFlags::EUC_JP | RegularExpressionFlags::WINDOWS_31J | RegularExpressionFlags::UTF_8)
      o |= Regexp::NOENCODING if flags.anybits?(RegularExpressionFlags::ASCII_8BIT)
      o
    end
  end

  class InterpolatedMatchLastLineNode < Node
    include RegularExpressionOptions
  end

  class InterpolatedRegularExpressionNode < Node
    include RegularExpressionOptions
  end

  class MatchLastLineNode < Node
    include RegularExpressionOptions
  end

  class RegularExpressionNode < Node
    include RegularExpressionOptions
  end

  private_constant :RegularExpressionOptions

  module HeredocQuery # :nodoc:
    # Returns true if this node was represented as a heredoc in the source code.
    def heredoc?
      opening&.start_with?("<<")
    end
  end

  class InterpolatedStringNode < Node
    include HeredocQuery
  end

  class InterpolatedXStringNode < Node
    include HeredocQuery
  end

  class StringNode < Node
    include HeredocQuery

    # Occasionally it's helpful to treat a string as if it were interpolated so
    # that there's a consistent interface for working with strings.
    def to_interpolated
      InterpolatedStringNode.new(
        source,
        frozen? ? InterpolatedStringNodeFlags::FROZEN : 0,
        opening_loc,
        [copy(opening_loc: nil, closing_loc: nil, location: content_loc)],
        closing_loc,
        location
      )
    end
  end

  class XStringNode < Node
    include HeredocQuery

    # Occasionally it's helpful to treat a string as if it were interpolated so
    # that there's a consistent interface for working with strings.
    def to_interpolated
      InterpolatedXStringNode.new(
        source,
        opening_loc,
        [StringNode.new(source, 0, nil, content_loc, nil, unescaped, content_loc)],
        closing_loc,
        location
      )
    end
  end

  private_constant :HeredocQuery

  class ImaginaryNode < Node
    # Returns the value of the node as a Ruby Complex.
    def value
      Complex(0, numeric.value)
    end
  end

  class RationalNode < Node
    # Returns the value of the node as a Ruby Rational.
    def value
      Rational(numeric.is_a?(IntegerNode) ? numeric.value : slice.chomp("r"))
    end
  end

  class ConstantReadNode < Node
    # Returns the list of parts for the full name of this constant.
    # For example: [:Foo]
    def full_name_parts
      [name]
    end

    # Returns the full name of this constant. For example: "Foo"
    def full_name
      name.to_s
    end
  end

  class ConstantWriteNode < Node
    # Returns the list of parts for the full name of this constant.
    # For example: [:Foo]
    def full_name_parts
      [name]
    end

    # Returns the full name of this constant. For example: "Foo"
    def full_name
      name.to_s
    end
  end

  class ConstantPathNode < Node
    # An error class raised when dynamic parts are found while computing a
    # constant path's full name. For example:
    # Foo::Bar::Baz -> does not raise because all parts of the constant path are
    # simple constants
    # var::Bar::Baz -> raises because the first part of the constant path is a
    # local variable
    class DynamicPartsInConstantPathError < StandardError; end

    # An error class raised when missing nodes are found while computing a
    # constant path's full name. For example:
    # Foo:: -> raises because the constant path is missing the last part
    class MissingNodesInConstantPathError < StandardError; end

    # Returns the list of parts for the full name of this constant path.
    # For example: [:Foo, :Bar]
    def full_name_parts
      parts = [] #: Array[Symbol]
      current = self #: node?

      while current.is_a?(ConstantPathNode)
        name = current.name
        if name.nil?
          raise MissingNodesInConstantPathError, "Constant path contains missing nodes. Cannot compute full name"
        end

        parts.unshift(name)
        current = current.parent
      end

      if !current.is_a?(ConstantReadNode) && !current.nil?
        raise DynamicPartsInConstantPathError, "Constant path contains dynamic parts. Cannot compute full name"
      end

      parts.unshift(current&.name || :"")
    end

    # Returns the full name of this constant path. For example: "Foo::Bar"
    def full_name
      full_name_parts.join("::")
    end

    # Previously, we had a child node on this class that contained either a
    # constant read or a missing node. To not cause a breaking change, we
    # continue to supply that API.
    def child
      warn(<<~MSG, category: :deprecated)
        DEPRECATED: ConstantPathNode#child is deprecated and will be removed \
        in the next major version. Use \
        ConstantPathNode#name/ConstantPathNode#name_loc instead. Called from \
        #{caller(1..1).first}.
      MSG

      name ? ConstantReadNode.new(source, name, name_loc) : MissingNode.new(source, location)
    end
  end

  class ConstantPathTargetNode < Node
    # Returns the list of parts for the full name of this constant path.
    # For example: [:Foo, :Bar]
    def full_name_parts
      parts =
        case parent
        when ConstantPathNode, ConstantReadNode
          parent.full_name_parts
        when nil
          [:""]
        else
          # e.g. self::Foo, (var)::Bar = baz
          raise ConstantPathNode::DynamicPartsInConstantPathError, "Constant target path contains dynamic parts. Cannot compute full name"
        end

      if name.nil?
        raise ConstantPathNode::MissingNodesInConstantPathError, "Constant target path contains missing nodes. Cannot compute full name"
      end

      parts.push(name)
    end

    # Returns the full name of this constant path. For example: "Foo::Bar"
    def full_name
      full_name_parts.join("::")
    end

    # Previously, we had a child node on this class that contained either a
    # constant read or a missing node. To not cause a breaking change, we
    # continue to supply that API.
    def child
      warn(<<~MSG, category: :deprecated)
        DEPRECATED: ConstantPathTargetNode#child is deprecated and will be \
        removed in the next major version. Use \
        ConstantPathTargetNode#name/ConstantPathTargetNode#name_loc instead. \
        Called from #{caller(1..1).first}.
      MSG

      name ? ConstantReadNode.new(source, name, name_loc) : MissingNode.new(source, location)
    end
  end

  class ConstantTargetNode < Node
    # Returns the list of parts for the full name of this constant.
    # For example: [:Foo]
    def full_name_parts
      [name]
    end

    # Returns the full name of this constant. For example: "Foo"
    def full_name
      name.to_s
    end
  end

  class ParametersNode < Node
    # Mirrors the Method#parameters method.
    def signature
      names = [] #: Array[[Symbol, Symbol] | [Symbol]]

      requireds.each do |param|
        names << (param.is_a?(MultiTargetNode) ? [:req] : [:req, param.name])
      end

      optionals.each { |param| names << [:opt, param.name] }

      if rest && rest.is_a?(RestParameterNode)
        names << [:rest, rest.name || :*]
      end

      posts.each do |param|
        if param.is_a?(MultiTargetNode)
          names << [:req]
        elsif param.is_a?(NoKeywordsParameterNode)
          # Invalid syntax, e.g. "def f(**nil, ...)" moves the NoKeywordsParameterNode to posts
          raise "Invalid syntax"
        else
          names << [:req, param.name]
        end
      end

      # Regardless of the order in which the keywords were defined, the required
      # keywords always come first followed by the optional keywords.
      keyopt = [] #: Array[OptionalKeywordParameterNode]
      keywords.each do |param|
        if param.is_a?(OptionalKeywordParameterNode)
          keyopt << param
        else
          names << [:keyreq, param.name]
        end
      end

      keyopt.each { |param| names << [:key, param.name] }

      case keyword_rest
      when ForwardingParameterNode
        names.concat([[:rest, :*], [:keyrest, :**], [:block, :&]])
      when KeywordRestParameterNode
        names << [:keyrest, keyword_rest.name || :**]
      when NoKeywordsParameterNode
        names << [:nokey]
      end

      names << [:block, block.name || :&] if block
      names
    end
  end
end
