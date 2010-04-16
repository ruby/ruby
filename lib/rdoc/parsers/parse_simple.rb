# Parse a non-source file. We basically take the whole thing
# as one big comment. If the first character in the file
# is '#', we strip leading pound signs.


require "rdoc/code_objects"
require "rdoc/markup/simple_markup/preprocess"

module RDoc
  # See rdoc/parsers/parse_c.rb

  class SimpleParser

    # prepare to parse a plain file
    def initialize(top_level, file_name, body, options, stats)

      preprocess = SM::PreProcess.new(file_name, options.rdoc_include)

      preprocess.handle(body) do |directive, param|
        $stderr.puts "Unrecognized directive '#{directive}' in #{file_name}"
      end

      @body = body
      @options = options
      @top_level = top_level
    end

    # Extract the file contents and attach them to the toplevel as a
    # comment

    def scan
      #    @body.gsub(/^(\s\n)+/, '')
      @top_level.comment = remove_private_comments(@body)
      @top_level
    end

    def remove_private_comments(comment)
      comment.gsub(/^--.*?^\+\+/m, '').sub(/^--.*/m, '')
    end
  end
end
