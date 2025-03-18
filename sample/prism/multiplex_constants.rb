# This script indexes the classes and modules within a set of files using the
# saved source functionality.

require "prism"
require "etc"
require "tempfile"

module Indexer
  # A class that implements the #enter functionality so that it can be passed to
  # the various save* APIs. This effectively bundles up all of the node_id and
  # field_name pairs so that they can be written back to the parent process.
  class Repository
    attr_reader :scope, :entries

    def initialize
      @scope = []
      @entries = []
    end

    def with(next_scope)
      previous_scope = scope
      @scope = scope + next_scope
      yield
      @scope = previous_scope
    end

    def empty?
      entries.empty?
    end

    def enter(node_id, field_name)
      entries << [scope.join("::"), node_id, field_name]
    end
  end

  # Visit the classes and modules in the AST and save their locations into the
  # repository.
  class Visitor < Prism::Visitor
    attr_reader :repository

    def initialize(repository)
      @repository = repository
    end

    def visit_class_node(node)
      repository.with(node.constant_path.full_name_parts) do
        node.constant_path.save_location(repository)
        visit(node.body)
      end
    end

    def visit_module_node(node)
      repository.with(node.constant_path.full_name_parts) do
        node.constant_path.save_location(repository)
        visit(node.body)
      end
    end
  end

  # Index the classes and modules within a file. If there are any entries,
  # return them as a serialized string to the parent process.
  def self.index(filepath)
    repository = Repository.new
    Prism.parse_file(filepath).value.accept(Visitor.new(repository))
    "#{filepath}|#{repository.entries.join("|")}" unless repository.empty?
  end
end

def index_glob(glob, count = Etc.nprocessors - 1)
  process_ids = []
  filepath_writers = []
  index_reader, index_writer = IO.pipe

  # For each number in count, fork off a worker that has access to two pipes.
  # The first pipe is the index_writer, to which it writes all of the results of
  # indexing the various files. The second pipe is the filepath_reader, from
  # which it reads the filepaths that it needs to index.
  count.times do
    filepath_reader, filepath_writer = IO.pipe

    process_ids << fork do
      filepath_writer.close
      index_reader.close

      while (filepath = filepath_reader.gets(chomp: true))
        results = Indexer.index(filepath)
        index_writer.puts(results) if results
      end
    end

    filepath_reader.close
    filepath_writers << filepath_writer
  end

  index_writer.close

  # In a separate thread, write all of the filepaths to the various worker
  # processes. This is done in a separate threads since puts will eventually
  # block when each of the pipe buffers fills up. We write in a round-robin
  # fashion to the various workers. This could be improved using a work-stealing
  # algorithm, but is fine if you don't end up having a ton of variety in the
  # size of your files.
  writer_thread =
    Thread.new do
      Dir[glob].each_with_index do |filepath, index|
        filepath_writers[index % count].puts(filepath)
      end
    end

  index = Hash.new { |hash, key| hash[key] = [] }

  # In a separate thread, read all of the results from the various worker
  # processes and store them in the index. This is done in a separate thread so
  # that reads and writes can be interleaved. This is important so that the
  # index pipe doesn't fill up and block the writer.
  reader_thread =
    Thread.new do
      while (line = index_reader.gets(chomp: true))
        filepath, *entries = line.split("|")
        repository = Prism::Relocation.filepath(filepath).filepath.lines.code_unit_columns(Encoding::UTF_16LE).leading_comments

        entries.each_slice(3) do |(name, node_id, field_name)|
          index[name] << repository.enter(Integer(node_id), field_name.to_sym)
        end
      end
    end

  writer_thread.join
  filepath_writers.each(&:close)

  reader_thread.join
  index_reader.close

  process_ids.each { |process_id| Process.wait(process_id) }
  index
end

index_glob(File.expand_path("../../lib/**/*.rb", __dir__))
