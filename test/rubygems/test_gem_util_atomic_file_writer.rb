# frozen_string_literal: true

require_relative "helper"
require "rubygems/util/atomic_file_writer"

class TestGemUtilAtomicFileWriter < Gem::TestCase
  def test_external_encoding
    Gem::AtomicFileWriter.open(File.join(@tempdir, "test.txt")) do |file|
      assert_equal(Encoding::ASCII_8BIT, file.external_encoding)
    end
  end
end
