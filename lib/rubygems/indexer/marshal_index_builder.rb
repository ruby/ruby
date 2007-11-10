require 'rubygems/indexer'

# Construct the master Gem index file.
class Gem::Indexer::MarshalIndexBuilder < Gem::Indexer::MasterIndexBuilder
  def end_index
    @file.write @index.dump
  end
end
