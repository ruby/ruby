# This script finds the declaration of all classes and modules and stores them
# in a hash for an in-memory database of constants.

require "prism"

class RelocationVisitor < Prism::Visitor
  attr_reader :index, :repository, :scope

  def initialize(index, repository, scope = [])
    @index = index
    @repository = repository
    @scope = scope
  end

  def visit_class_node(node)
    next_scope = scope + node.constant_path.full_name_parts
    index[next_scope.join("::")] << node.constant_path.save(repository)
    node.body&.accept(RelocationVisitor.new(index, repository, next_scope))
  end

  def visit_module_node(node)
    next_scope = scope + node.constant_path.full_name_parts
    index[next_scope.join("::")] << node.constant_path.save(repository)
    node.body&.accept(RelocationVisitor.new(index, repository, next_scope))
  end
end

# Create an index that will store a mapping between the names of constants to a
# list of the locations where they are declared or re-opened.
index = Hash.new { |hash, key| hash[key] = [] }

# Loop through every file in the lib directory of this repository and parse them
# with Prism. Then visit them using the RelocateVisitor to store their
# repository entries in the index.
Dir[File.expand_path("../../lib/**/*.rb", __dir__)].each do |filepath|
  repository = Prism::Relocation.filepath(filepath).filepath.lines.code_unit_columns(Encoding::UTF_16LE)
  Prism.parse_file(filepath).value.accept(RelocationVisitor.new(index, repository))
end

puts index["Prism::ParametersNode"].map { |entry| "#{entry.filepath}:#{entry.start_line}:#{entry.start_code_units_column}" }
# =>
# prism/lib/prism/node.rb:13889:8
# prism/lib/prism/node_ext.rb:267:8
