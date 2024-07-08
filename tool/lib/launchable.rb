# frozen_string_literal: true
require 'json'
require 'uri'

module Launchable
  ##
  # JsonStreamWriter writes a JSON file using a stream.
  # By utilizing a stream, we can minimize memory usage, especially for large files.
  class JsonStreamWriter
    def initialize(path)
      @file = File.open(path, "w")
      @file.write("{")
      @indent_level = 0
      @is_first_key_val = true
      @is_first_obj = true
      write_new_line
    end

    def write_object obj
      if @is_first_obj
        @is_first_obj = false
      else
        write_comma
        write_new_line
      end
      @indent_level += 1
      @file.write(to_json_str(obj))
      @indent_level -= 1
      @is_first_key_val = true
      # Occasionally, invalid JSON will be created as shown below, especially when `--repeat-count` is specified.
      # {
      #   "testPath": "file=test%2Ftest_timeout.rb&class=TestTimeout&testcase=test_allows_zero_seconds",
      #   "status": "TEST_PASSED",
      #   "duration": 2.7e-05,
      #   "createdAt": "2024-02-09 12:21:07 +0000",
      #   "stderr": null,
      #   "stdout": null
      # }: null <- here
      # },
      # To prevent this, IO#flush is called here.
      @file.flush
    end

    def write_array(key)
      @indent_level += 1
      @file.write(to_json_str(key))
      write_colon
      @file.write(" ", "[")
      write_new_line
    end

    def close
      return if @file.closed?
      close_array
      @indent_level -= 1
      write_new_line
      @file.write("}", "\n")
      @file.flush
      @file.close
    end

    private
    def to_json_str(obj)
      json = JSON.pretty_generate(obj)
      json.gsub(/^/, ' ' * (2 * @indent_level))
    end

    def write_indent
      @file.write(" " * 2 * @indent_level)
    end

    def write_new_line
      @file.write("\n")
    end

    def write_comma
      @file.write(',')
    end

    def write_colon
      @file.write(":")
    end

    def close_array
      write_new_line
      write_indent
      @file.write("]")
      @indent_level -= 1
    end
  end
end
