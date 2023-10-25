require "tempfile"
require "test/unit"

require "csv"

require_relative "../lib/with_different_ofs"

module CSVHelper
  def with_chunk_size(chunk_size)
    chunk_size_keep = ENV["CSV_PARSER_SCANNER_TEST_CHUNK_SIZE"]
    begin
      ENV["CSV_PARSER_SCANNER_TEST_CHUNK_SIZE"] = chunk_size
      yield
    ensure
      ENV["CSV_PARSER_SCANNER_TEST_CHUNK_SIZE"] = chunk_size_keep
    end
  end

  def with_verbose(verbose)
    original = $VERBOSE
    begin
      $VERBOSE = verbose
      yield
    ensure
      $VERBOSE = original
    end
  end

  def with_default_internal(encoding)
    original = Encoding.default_internal
    begin
      with_verbose(false) do
        Encoding.default_internal = encoding
      end
      yield
    ensure
      with_verbose(false) do
        Encoding.default_internal = original
      end
    end
  end
end
