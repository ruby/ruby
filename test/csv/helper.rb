require "tempfile"
require "test/unit"

require "csv"

require_relative "../lib/with_different_ofs.rb"

module Helper
  def with_chunk_size(chunk_size)
    chunk_size_keep = ENV["CSV_PARSER_SCANNER_TEST_CHUNK_SIZE"]
    begin
      ENV["CSV_PARSER_SCANNER_TEST_CHUNK_SIZE"] = chunk_size
      yield
    ensure
      ENV["CSV_PARSER_SCANNER_TEST_CHUNK_SIZE"] = chunk_size_keep
    end
  end
end
