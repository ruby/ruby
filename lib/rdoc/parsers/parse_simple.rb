require 'rdoc'
require 'rdoc/code_objects'
require 'rdoc/markup/preprocess'

##
# Parse a non-source file. We basically take the whole thing as one big
# comment. If the first character in the file is '#', we strip leading pound
# signs.

class RDoc::SimpleParser

  ##
  # Prepare to parse a plain file

  def initialize(top_level, file_name, body, options, stats)
    preprocess = RDoc::Markup::PreProcess.new(file_name, options.rdoc_include)

    preprocess.handle(body) do |directive, param|
      warn "Unrecognized directive '#{directive}' in #{file_name}"
    end

    @body = body
    @options = options
    @top_level = top_level
  end

  ##
  # Extract the file contents and attach them to the toplevel as a comment

  def scan
    @top_level.comment = remove_private_comments(@body)
    @top_level
  end

  def remove_private_comments(comment)
    comment.gsub(/^--[^-].*?^\+\+/m, '').sub(/^--.*/m, '')
  end

end

