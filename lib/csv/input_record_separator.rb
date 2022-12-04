require "English"
require "stringio"

class CSV
  module InputRecordSeparator
    class << self
      is_input_record_separator_deprecated = false
      verbose, $VERBOSE = $VERBOSE, true
      stderr, $stderr = $stderr, StringIO.new
      input_record_separator = $INPUT_RECORD_SEPARATOR
      begin
        $INPUT_RECORD_SEPARATOR = "\r\n"
        is_input_record_separator_deprecated = (not $stderr.string.empty?)
      ensure
        $INPUT_RECORD_SEPARATOR = input_record_separator
        $stderr = stderr
        $VERBOSE = verbose
      end

      if is_input_record_separator_deprecated
        def value
          "\n"
        end
      else
        def value
          $INPUT_RECORD_SEPARATOR
        end
      end
    end
  end
end
