#!/usr/bin/env ruby
# typed: false

require "erb"
require "fileutils"
require "yaml"

module Prism
  module Template
    SERIALIZE_ONLY_SEMANTICS_FIELDS = ENV.fetch("PRISM_SERIALIZE_ONLY_SEMANTICS_FIELDS", false)
    CHECK_FIELD_KIND = ENV.fetch("CHECK_FIELD_KIND", false)

    JAVA_BACKEND = ENV["PRISM_JAVA_BACKEND"] || "truffleruby"
    JAVA_STRING_TYPE = JAVA_BACKEND == "jruby" ? "org.jruby.RubySymbol" : "String"

    class Error
      attr_reader :name

      def initialize(name)
        @name = name
      end
    end

    class Warning
      attr_reader :name

      def initialize(name)
        @name = name
      end
    end

    # This module contains methods for escaping characters in JavaDoc comments.
    module JavaDoc
      ESCAPES = {
        "'" => "&#39;",
        "\"" => "&quot;",
        "@" => "&#64;",
        "&" => "&amp;",
        "<" => "&lt;",
        ">" => "&gt;"
      }.freeze

      def self.escape(value)
        value.gsub(/['&"<>@]/, ESCAPES)
      end
    end

    # A comment attached to a field or node.
    class ConfigComment
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def each_line(&block)
        value.each_line { |line| yield line.prepend(" ").rstrip }
      end

      def each_java_line(&block)
        ConfigComment.new(JavaDoc.escape(value)).each_line(&block)
      end
    end

    # This represents a field on a node. It contains all of the necessary
    # information to template out the code for that field.
    class Field
      attr_reader :name, :comment, :options

      def initialize(name:, comment: nil, **options)
        @name = name
        @comment = comment
        @options = options
      end

      def each_comment_line(&block)
        ConfigComment.new(comment).each_line(&block) if comment
      end

      def each_comment_java_line(&block)
        ConfigComment.new(comment).each_java_line(&block) if comment
      end

      def semantic_field?
        true
      end

      def should_be_serialized?
        SERIALIZE_ONLY_SEMANTICS_FIELDS ? semantic_field? : true
      end
    end

    # Some node fields can be specialized if they point to a specific kind of
    # node and not just a generic node.
    class NodeKindField < Field
      def c_type
        if specific_kind
          "pm_#{specific_kind.gsub(/(?<=.)[A-Z]/, "_\\0").downcase}"
        else
          "pm_node"
        end
      end

      def ruby_type
        specific_kind || "Node"
      end

      def java_type
        specific_kind || "Node"
      end

      def java_cast
        if specific_kind
          "(Nodes.#{options[:kind]}) "
        else
          ""
        end
      end

      def specific_kind
        options[:kind] unless options[:kind].is_a?(Array)
      end

      def union_kind
        options[:kind] if options[:kind].is_a?(Array)
      end
    end

    # This represents a field on a node that is itself a node. We pass them as
    # references and store them as references.
    class NodeField < NodeKindField
      def rbs_class
        if specific_kind
          specific_kind
        elsif union_kind
          union_kind.join(" | ")
        else
          "Prism::node"
        end
      end

      def rbi_class
        if specific_kind
          "Prism::#{specific_kind}"
        elsif union_kind
          "T.any(#{union_kind.map { |kind| "Prism::#{kind}" }.join(", ")})"
        else
          "Prism::Node"
        end
      end

      def check_field_kind
        if union_kind
          "[#{union_kind.join(', ')}].include?(#{name}.class)"
        else
          "#{name}.is_a?(#{ruby_type})"
        end
      end
    end

    # This represents a field on a node that is itself a node and can be
    # optionally null. We pass them as references and store them as references.
    class OptionalNodeField < NodeKindField
      def rbs_class
        if specific_kind
          "#{specific_kind}?"
        elsif union_kind
          [*union_kind, "nil"].join(" | ")
        else
          "Prism::node?"
        end
      end

      def rbi_class
        if specific_kind
          "T.nilable(Prism::#{specific_kind})"
        elsif union_kind
          "T.nilable(T.any(#{union_kind.map { |kind| "Prism::#{kind}" }.join(", ")}))"
        else
          "T.nilable(Prism::Node)"
        end
      end

      def check_field_kind
        if union_kind
          "[#{union_kind.join(', ')}, NilClass].include?(#{name}.class)"
        else
          "#{name}.nil? || #{name}.is_a?(#{ruby_type})"
        end
      end
    end

    # This represents a field on a node that is a list of nodes. We pass them as
    # references and store them directly on the struct.
    class NodeListField < NodeKindField
      def rbs_class
        if specific_kind
          "Array[#{specific_kind}]"
        elsif union_kind
          "Array[#{union_kind.join(" | ")}]"
        else
          "Array[Prism::node]"
        end
      end

      def rbi_class
        if specific_kind
          "T::Array[Prism::#{specific_kind}]"
        elsif union_kind
          "T::Array[T.any(#{union_kind.map { |kind| "Prism::#{kind}" }.join(", ")})]"
        else
          "T::Array[Prism::Node]"
        end
      end

      def java_type
        "#{super}[]"
      end

      def check_field_kind
        if union_kind
          "#{name}.all? { |n| [#{union_kind.join(', ')}].include?(n.class) }"
        else
          "#{name}.all? { |n| n.is_a?(#{ruby_type}) }"
        end
      end
    end

    # This represents a field on a node that is the ID of a string interned
    # through the parser's constant pool.
    class ConstantField < Field
      def rbs_class
        "Symbol"
      end

      def rbi_class
        "Symbol"
      end

      def java_type
        JAVA_STRING_TYPE
      end
    end

    # This represents a field on a node that is the ID of a string interned
    # through the parser's constant pool and can be optionally null.
    class OptionalConstantField < Field
      def rbs_class
        "Symbol?"
      end

      def rbi_class
        "T.nilable(Symbol)"
      end

      def java_type
        JAVA_STRING_TYPE
      end
    end

    # This represents a field on a node that is a list of IDs that are associated
    # with strings interned through the parser's constant pool.
    class ConstantListField < Field
      def rbs_class
        "Array[Symbol]"
      end

      def rbi_class
        "T::Array[Symbol]"
      end

      def java_type
        "#{JAVA_STRING_TYPE}[]"
      end
    end

    # This represents a field on a node that is a string.
    class StringField < Field
      def rbs_class
        "String"
      end

      def rbi_class
        "String"
      end

      def java_type
        "byte[]"
      end
    end

    # This represents a field on a node that is a location.
    class LocationField < Field
      def semantic_field?
        false
      end

      def rbs_class
        "Location"
      end

      def rbi_class
        "Prism::Location"
      end

      def java_type
        "Location"
      end
    end

    # This represents a field on a node that is a location that is optional.
    class OptionalLocationField < Field
      def semantic_field?
        false
      end

      def rbs_class
        "Location?"
      end

      def rbi_class
        "T.nilable(Prism::Location)"
      end

      def java_type
        "Location"
      end
    end

    # This represents an integer field.
    class UInt8Field < Field
      def rbs_class
        "Integer"
      end

      def rbi_class
        "Integer"
      end

      def java_type
        "int"
      end
    end

    # This represents an integer field.
    class UInt32Field < Field
      def rbs_class
        "Integer"
      end

      def rbi_class
        "Integer"
      end

      def java_type
        "int"
      end
    end

    # This represents a set of flags. It is very similar to the UInt32Field, but
    # can be directly embedded into the flags field on the struct and provides
    # convenient methods for checking if a flag is set.
    class FlagsField < Field
      def rbs_class
        "Integer"
      end

      def rbi_class
        "Integer"
      end

      def java_type
        "short"
      end

      def kind
        options.fetch(:kind)
      end
    end

    # This represents an arbitrarily-sized integer. When it gets to Ruby it will
    # be an Integer.
    class IntegerField < Field
      def rbs_class
        "Integer"
      end

      def rbi_class
        "Integer"
      end

      def java_type
        "Object"
      end
    end

    # This represents a double-precision floating point number. When it gets to
    # Ruby it will be a Float.
    class DoubleField < Field
      def rbs_class
        "Float"
      end

      def rbi_class
        "Float"
      end

      def java_type
        "double"
      end
    end

    # This class represents a node in the tree, configured by the config.yml file
    # in YAML format. It contains information about the name of the node and the
    # various child nodes it contains.
    class NodeType
      attr_reader :name, :type, :human, :fields, :newline, :comment

      def initialize(config)
        @name = config.fetch("name")

        type = @name.gsub(/(?<=.)[A-Z]/, "_\\0")
        @type = "PM_#{type.upcase}"
        @human = type.downcase

        @fields =
          config.fetch("fields", []).map do |field|
            type = field_type_for(field.fetch("type"))

            options = field.transform_keys(&:to_sym)
            options.delete(:type)

            # If/when we have documentation on every field, this should be changed
            # to use fetch instead of delete.
            comment = options.delete(:comment)

            type.new(comment: comment, **options)
          end

        @newline = config.fetch("newline", true)
        @comment = config.fetch("comment")
      end

      def each_comment_line(&block)
        ConfigComment.new(comment).each_line(&block)
      end

      def each_comment_java_line(&block)
        ConfigComment.new(comment).each_java_line(&block)
      end

      def semantic_fields
        @semantic_fields ||= @fields.select(&:semantic_field?)
      end

      # Should emit serialized length of node so implementations can skip
      # the node to enable lazy parsing.
      def needs_serialized_length?
        name == "DefNode"
      end

      private

      def field_type_for(name)
        case name
        when "node"       then NodeField
        when "node?"      then OptionalNodeField
        when "node[]"     then NodeListField
        when "string"     then StringField
        when "constant"   then ConstantField
        when "constant?"  then OptionalConstantField
        when "constant[]" then ConstantListField
        when "location"   then LocationField
        when "location?"  then OptionalLocationField
        when "uint8"      then UInt8Field
        when "uint32"     then UInt32Field
        when "flags"      then FlagsField
        when "integer"    then IntegerField
        when "double"     then DoubleField
        else raise("Unknown field type: #{name.inspect}")
        end
      end
    end

    # This represents a token in the lexer.
    class Token
      attr_reader :name, :value, :comment

      def initialize(config)
        @name = config.fetch("name")
        @value = config["value"]
        @comment = config.fetch("comment")
      end
    end

    # Represents a set of flags that should be internally represented with an enum.
    class Flags
      # Represents an individual flag within a set of flags.
      class Flag
        attr_reader :name, :camelcase, :comment

        def initialize(config)
          @name = config.fetch("name")
          @camelcase = @name.split("_").map(&:capitalize).join
          @comment = config.fetch("comment")
        end
      end

      attr_reader :name, :human, :values, :comment

      def initialize(config)
        @name = config.fetch("name")
        @human = @name.gsub(/(?<=.)[A-Z]/, "_\\0").downcase
        @values = config.fetch("values").map { |flag| Flag.new(flag) }
        @comment = config.fetch("comment")
      end
    end

    class << self
      # This templates out a file using ERB with the given locals. The locals are
      # derived from the config.yml file.
      def render(name, write_to: nil)
        filepath = "templates/#{name}.erb"
        template = File.expand_path("../#{filepath}", __dir__)

        erb = read_template(template)
        extension = File.extname(filepath.gsub(".erb", ""))

        heading =
          case extension
          when ".rb"
            <<~HEADING
            # frozen_string_literal: true

            =begin
            This file is generated by the templates/template.rb script and should not be
            modified manually. See #{filepath}
            if you are looking to modify the template
            =end

            HEADING
          when ".rbs"
            <<~HEADING
            # This file is generated by the templates/template.rb script and should not be
            # modified manually. See #{filepath}
            # if you are looking to modify the template

            HEADING
          when ".rbi"
            <<~HEADING
            # typed: strict

            =begin
            This file is generated by the templates/template.rb script and should not be
            modified manually. See #{filepath}
            if you are looking to modify the template
            =end

            HEADING
          else
            <<~HEADING
            /******************************************************************************/
            /* This file is generated by the templates/template.rb script and should not  */
            /* be modified manually. See                                                  */
            /* #{filepath + " " * (74 - filepath.size) } */
            /* if you are looking to modify the                                           */
            /* template                                                                   */
            /******************************************************************************/

            HEADING
          end

        write_to ||= File.expand_path("../#{name}", __dir__)
        contents = heading + erb.result_with_hash(locals)

        if (extension == ".c" || extension == ".h") && !contents.ascii_only?
          # Enforce that we only have ASCII characters here. This is necessary
          # for non-UTF-8 locales that only allow ASCII characters in C source
          # files.
          contents.each_line.with_index(1) do |line, line_number|
            raise "Non-ASCII character on line #{line_number} of #{write_to}" unless line.ascii_only?
          end
        end

        FileUtils.mkdir_p(File.dirname(write_to))
        File.write(write_to, contents)
      end

      private

      def read_template(filepath)
        template = File.read(filepath, encoding: Encoding::UTF_8)
        erb = erb(template)
        erb.filename = filepath
        erb
      end

      def erb(template)
        ERB.new(template, trim_mode: "-")
      end

      def locals
        @locals ||=
          begin
            config = YAML.load_file(File.expand_path("../config.yml", __dir__))

            {
              errors: config.fetch("errors").map { |name| Error.new(name) },
              warnings: config.fetch("warnings").map { |name| Warning.new(name) },
              nodes: config.fetch("nodes").map { |node| NodeType.new(node) }.sort_by(&:name),
              tokens: config.fetch("tokens").map { |token| Token.new(token) },
              flags: config.fetch("flags").map { |flags| Flags.new(flags) }
            }
          end
      end
    end

    TEMPLATES = [
      "ext/prism/api_node.c",
      "include/prism/ast.h",
      "include/prism/diagnostic.h",
      "javascript/src/deserialize.js",
      "javascript/src/nodes.js",
      "javascript/src/visitor.js",
      "java/org/prism/Loader.java",
      "java/org/prism/Nodes.java",
      "java/org/prism/AbstractNodeVisitor.java",
      "lib/prism/compiler.rb",
      "lib/prism/dispatcher.rb",
      "lib/prism/dot_visitor.rb",
      "lib/prism/dsl.rb",
      "lib/prism/inspect_visitor.rb",
      "lib/prism/mutation_compiler.rb",
      "lib/prism/node.rb",
      "lib/prism/reflection.rb",
      "lib/prism/serialize.rb",
      "lib/prism/visitor.rb",
      "src/diagnostic.c",
      "src/node.c",
      "src/prettyprint.c",
      "src/serialize.c",
      "src/token_type.c",
      "rbi/prism/node.rbi",
      "rbi/prism/visitor.rbi",
      "sig/prism.rbs",
      "sig/prism/dsl.rbs",
      "sig/prism/mutation_compiler.rbs",
      "sig/prism/node.rbs",
      "sig/prism/visitor.rbs",
      "sig/prism/_private/dot_visitor.rbs"
    ]
  end
end

if __FILE__ == $0
  if ARGV.empty?
    Prism::Template::TEMPLATES.each { |filepath| Prism::Template.render(filepath) }
  else # ruby/ruby
    name, write_to = ARGV
    Prism::Template.render(name, write_to: write_to)
  end
end
