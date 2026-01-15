# This script generates a tags file using Prism to parse the Ruby files.

require "prism"

# This visitor is responsible for visiting the nodes in the AST and generating
# the appropriate tags. The tags are stored in the entries array as strings.
class TagsVisitor < Prism::Visitor
  # This represents an entry in the tags file, which is a tab-separated line. It
  # houses the logic for how an entry is constructed.
  class Entry
    attr_reader :parts

    def initialize(name, filepath, pattern, type)
      @parts = [name, filepath, pattern, type]
    end

    def attribute(key, value)
      parts << "#{key}:#{value}"
    end

    def attribute_class(nesting, names)
      return if nesting.empty? && names.length == 1
      attribute("class", [*nesting, names].flatten.tap(&:pop).join("."))
    end

    def attribute_inherits(names)
      attribute("inherits", names.join(".")) if names
    end

    def to_line
      parts.join("\t")
    end
  end

  private_constant :Entry

  attr_reader :entries, :filepath, :lines, :nesting, :singleton

  # Initialize the visitor with the given parameters. The first three parameters
  # are constant throughout the visit, while the last two are controlled by the
  # visitor as it traverses the AST. These are treated as immutable by virtue of
  # the visit methods constructing new visitors when they need to change.
  def initialize(entries, filepath, lines, nesting = [], singleton = false)
    @entries = entries
    @filepath = filepath
    @lines = lines
    @nesting = nesting
    @singleton = singleton
  end

  # Visit a method alias node and generate the appropriate tags.
  #
  #     alias m2 m1
  #
  def visit_alias_method_node(node)
    enter(node.new_name.unescaped.to_sym, node, "a") do |entry|
      entry.attribute_class(nesting, [nil])
    end

    super
  end

  # Visit a method call to attr_reader, attr_writer, or attr_accessor without a
  # receiver and generate the appropriate tags. Note that this ignores the fact
  # that these methods could be overridden, which is a limitation of this
  # script.
  #
  #     attr_accessor :m1
  #
  def visit_call_node(node)
    if !node.receiver && %i[attr_reader attr_writer attr_accessor].include?(name = node.name)
      (node.arguments&.arguments || []).grep(Prism::SymbolNode).each do |argument|
        if name != :attr_writer
          enter(:"#{argument.unescaped}", argument, singleton ? "F" : "f") do |entry|
            entry.attribute_class(nesting, [nil])
          end
        end

        if name != :attr_reader
          enter(:"#{argument.unescaped}=", argument, singleton ? "F" : "f") do |entry|
            entry.attribute_class(nesting, [nil])
          end
        end
      end
    end

    super
  end

  # Visit a class node and generate the appropriate tags.
  #
  #     class C1
  #     end
  #
  def visit_class_node(node)
    if (names = names_for(node.constant_path))
      enter(names.last, node, "c") do |entry|
        entry.attribute_class(nesting, names)
        entry.attribute_inherits(names_for(node.superclass))
      end

      node.body&.accept(copy_visitor([*nesting, names], singleton))
    end
  end

  # Visit a constant path write node and generate the appropriate tags.
  #
  #     C1::C2 = 1
  #
  def visit_constant_path_write_node(node)
    if (names = names_for(node.target))
      enter(names.last, node, "C") do |entry|
        entry.attribute_class(nesting, names)
      end
    end

    super
  end

  # Visit a constant write node and generate the appropriate tags.
  #
  #     C1 = 1
  #
  def visit_constant_write_node(node)
    enter(node.name, node, "C") do |entry|
      entry.attribute_class(nesting, [nil])
    end

    super
  end

  # Visit a method definition node and generate the appropriate tags.
  #
  #     def m1; end
  #
  def visit_def_node(node)
    enter(node.name, node, (node.receiver || singleton) ? "F" : "f") do |entry|
      entry.attribute_class(nesting, [nil])
    end

    super
  end

  # Visit a module node and generate the appropriate tags.
  #
  #     module M1
  #     end
  #
  def visit_module_node(node)
    if (names = names_for(node.constant_path))
      enter(names.last, node, "m") do |entry|
        entry.attribute_class(nesting, names)
      end

      node.body&.accept(copy_visitor([*nesting, names], singleton))
    end
  end

  # Visit a singleton class node and generate the appropriate tags.
  #
  #     class << self
  #     end
  #
  def visit_singleton_class_node(node)
    case node.expression
    when Prism::SelfNode
      node.body&.accept(copy_visitor(nesting, true))
    when Prism::ConstantReadNode, Prism::ConstantPathNode
      if (names = names_for(node.expression))
        node.body&.accept(copy_visitor([*nesting, names], true))
      end
    else
      node.body&.accept(copy_visitor([*nesting, nil], true))
    end
  end

  private

  # Generate a new visitor with the given dynamic options. The static options
  # are copied over automatically.
  def copy_visitor(nesting, singleton)
    TagsVisitor.new(entries, filepath, lines, nesting, singleton)
  end

  # Generate a new entry for the given name, node, and type and add it into the
  # list of entries. The block is used to add additional attributes to the
  # entry.
  def enter(name, node, type)
    line = lines[node.location.start_line - 1].chomp
    pattern = "/^#{line.gsub("\\", "\\\\\\\\").gsub("/", "\\/")}$/;\""

    entry = Entry.new(name, filepath, pattern, type)
    yield entry

    entries << entry.to_line
  end

  # Retrieve the names for the given node. This is used to construct the class
  # attribute for the tags.
  def names_for(node)
    case node
    when Prism::ConstantPathNode
      names = names_for(node.parent)
      return unless names

      names << node.name
    when Prism::ConstantReadNode
      [node.name]
    when Prism::SelfNode
      [:self]
    else
      # dynamic
    end
  end
end

# Parse the Ruby file and visit all of the nodes in the resulting AST. Once all
# of the nodes have been visited, the entries array should be populated with the
# tags.
result = Prism.parse_stream(DATA)
result.value.accept(TagsVisitor.new(entries = [], __FILE__, result.source.lines))

# Print the tags to STDOUT.
puts "!_TAG_FILE_FORMAT	2	/extended format; --format=1 will not append ;\" to lines/"
puts "!_TAG_FILE_SORTED	1	/0=unsorted, 1=sorted, 2=foldcase/"
puts entries.sort

# =>
# !_TAG_FILE_FORMAT	2	/extended format; --format=1 will not append ;" to lines/
# !_TAG_FILE_SORTED	1	/0=unsorted, 1=sorted, 2=foldcase/
# C1	sample/prism/make_tags.rb	/^    class C1$/;"	c	class:M1.M2
# C2	sample/prism/make_tags.rb	/^      class C2 < Object$/;"	c	class:M1.M2.C1	inherits:Object
# C6	sample/prism/make_tags.rb	/^  C6 = 1$/;"	C	class:M1
# C7	sample/prism/make_tags.rb	/^  C7 = 2$/;"	C	class:M1
# C9	sample/prism/make_tags.rb	/^  C8::C9 = 3$/;"	C	class:M1.C8
# M1	sample/prism/make_tags.rb	/^module M1$/;"	m
# M2	sample/prism/make_tags.rb	/^  module M2$/;"	m	class:M1
# M4	sample/prism/make_tags.rb	/^  module M3::M4$/;"	m	class:M1.M3
# M5	sample/prism/make_tags.rb	/^  module self::M5$/;"	m	class:M1.self
# m1	sample/prism/make_tags.rb	/^        def m1; end$/;"	f	class:M1.M2.C1.C2
# m10	sample/prism/make_tags.rb	/^    attr_accessor :m10, :m11$/;"	f	class:M1.M3.M4
# m10=	sample/prism/make_tags.rb	/^    attr_accessor :m10, :m11$/;"	f	class:M1.M3.M4
# m11	sample/prism/make_tags.rb	/^    attr_accessor :m10, :m11$/;"	f	class:M1.M3.M4
# m11=	sample/prism/make_tags.rb	/^    attr_accessor :m10, :m11$/;"	f	class:M1.M3.M4
# m12	sample/prism/make_tags.rb	/^    attr_reader :m12, :m13, :m14$/;"	f	class:M1.M3.M4
# m13	sample/prism/make_tags.rb	/^    attr_reader :m12, :m13, :m14$/;"	f	class:M1.M3.M4
# m14	sample/prism/make_tags.rb	/^    attr_reader :m12, :m13, :m14$/;"	f	class:M1.M3.M4
# m15=	sample/prism/make_tags.rb	/^    attr_writer :m15$/;"	f	class:M1.M3.M4
# m2	sample/prism/make_tags.rb	/^        def m2; end$/;"	f	class:M1.M2.C1.C2
# m3	sample/prism/make_tags.rb	/^        alias m3 m1$/;"	a	class:M1.M2.C1.C2
# m4	sample/prism/make_tags.rb	/^        alias :m4 :m2$/;"	a	class:M1.M2.C1.C2
# m5	sample/prism/make_tags.rb	/^        def self.m5; end$/;"	F	class:M1.M2.C1.C2
# m6	sample/prism/make_tags.rb	/^          def m6; end$/;"	F	class:M1.M2.C1.C2
# m7	sample/prism/make_tags.rb	/^          def m7; end$/;"	F	class:M1.M2.C1.C2.C3
# m8	sample/prism/make_tags.rb	/^          def m8; end$/;"	F	class:M1.M2.C1.C2.C4.C5
# m9	sample/prism/make_tags.rb	/^          def m9; end$/;"	F	class:M1.M2.C1.C2.

__END__
module M1
  module M2
    class C1
      class C2 < Object
        def m1; end
        def m2; end

        alias m3 m1
        alias :m4 :m2

        def self.m5; end

        class << self
          def m6; end
        end

        class << C3
          def m7; end
        end

        class << C4::C5
          def m8; end
        end

        class << c
          def m9; end
        end
      end
    end
  end

  module M3::M4
    attr_accessor :m10, :m11
    attr_reader :m12, :m13, :m14
    attr_writer :m15
  end

  module self::M5
  end

  C6 = 1
  C7 = 2
  C8::C9 = 3
end
