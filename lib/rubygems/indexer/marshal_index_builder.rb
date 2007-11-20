require 'rubygems/indexer'

# Construct the master Gem index file.
class Gem::Indexer::MarshalIndexBuilder < Gem::Indexer::MasterIndexBuilder
  def end_index
    gems = {}
    index = Gem::SourceIndex.new

    @index.each do |name, gemspec|
      gems[gemspec.original_name] = gemspec
    end

    index.instance_variable_get(:@gems).replace gems

    @file.write index.dump
  end
end
