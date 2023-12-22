#!/usr/bin/env ruby

require "erb"
require "fileutils"
require "yaml"

module Prism
  SERIALIZE_ONLY_SEMANTICS_FIELDS = ENV.fetch("PRISM_SERIALIZE_ONLY_SEMANTICS_FIELDS", false)

  JAVA_BACKEND = ENV["PRISM_JAVA_BACKEND"] || "truffleruby"
  JAVA_STRING_TYPE = JAVA_BACKEND == "jruby" ? "org.jruby.RubySymbol" : "String"

  # This represents a field on a node. It contains all of the necessary
  # information to template out the code for that field.
  class Field
    attr_reader :name, :options

    def initialize(name:, type:, **options)
      @name, @type, @options = name, type, options
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
      if options[:kind]
        "pm_#{options[:kind].gsub(/(?<=.)[A-Z]/, "_\\0").downcase}"
      else
        "pm_node"
      end
    end

    def ruby_type
      options[:kind] || "Node"
    end

    def java_type
      options[:kind] || "Node"
    end

    def java_cast
      if options[:kind]
        "(Nodes.#{options[:kind]}) "
      else
        ""
      end
    end
  end

  # This represents a field on a node that is itself a node. We pass them as
  # references and store them as references.
  class NodeField < NodeKindField
    def rbs_class
      ruby_type
    end

    def rbi_class
      "Prism::#{ruby_type}"
    end
  end

  # This represents a field on a node that is itself a node and can be
  # optionally null. We pass them as references and store them as references.
  class OptionalNodeField < NodeKindField
    def rbs_class
      "#{ruby_type}?"
    end

    def rbi_class
      "T.nilable(Prism::#{ruby_type})"
    end
  end

  # This represents a field on a node that is a list of nodes. We pass them as
  # references and store them directly on the struct.
  class NodeListField < Field
    def rbs_class
      "Array[Node]"
    end

    def rbi_class
      "T::Array[Prism::Node]"
    end

    def java_type
      "Node[]"
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

  # This class represents a node in the tree, configured by the config.yml file in
  # YAML format. It contains information about the name of the node and the
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
          field_type_for(field.fetch("type")).new(**field.transform_keys(&:to_sym))
        end

      @newline = config.fetch("newline", true)
      @comment = config.fetch("comment")
    end

    def each_comment_line
      comment.each_line { |line| yield line.prepend(" ").rstrip }
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
    def template(name, write_to: nil)
      filepath = "templates/#{name}.erb"
      template = File.expand_path("../#{filepath}", __dir__)

      erb = read_template(template)
      extension = File.extname(filepath.gsub(".erb", ""))

      heading = case extension
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

    if ERB.instance_method(:initialize).parameters.assoc(:key) # Ruby 2.6+
      def erb(template)
        ERB.new(template, trim_mode: "-")
      end
    else
      def erb(template)
        ERB.new(template, nil, "-")
      end
    end

    def locals
      @locals ||=
        begin
          config = YAML.load_file(File.expand_path("../config.yml", __dir__))

          {
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
    "lib/prism/mutation_compiler.rb",
    "lib/prism/node.rb",
    "lib/prism/serialize.rb",
    "lib/prism/visitor.rb",
    "src/node.c",
    "src/prettyprint.c",
    "src/serialize.c",
    "src/token_type.c",
    "rbi/prism.rbi",
    "sig/prism.rbs",
  ]
end

if __FILE__ == $0
  if ARGV.empty?
    Prism::TEMPLATES.each { |filepath| Prism.template(filepath) }
  else # ruby/ruby
    name, write_to = ARGV
    Prism.template(name, write_to: write_to)
  end
end
