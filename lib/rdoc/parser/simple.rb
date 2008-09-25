require 'rdoc/parser'

##
# Parse a non-source file. We basically take the whole thing as one big
# comment. If the first character in the file is '#', we strip leading pound
# signs.

class RDoc::Parser::Simple < RDoc::Parser

  parse_files_matching(//)

  ##
  # Prepare to parse a plain file

  def initialize(top_level, file_name, content, options, stats)
    super

    preprocess = RDoc::Markup::PreProcess.new @file_name, @options.rdoc_include

    preprocess.handle @content do |directive, param|
      warn "Unrecognized directive '#{directive}' in #{@file_name}"
    end
  end

  ##
  # Extract the file contents and attach them to the toplevel as a comment

  def scan
    @top_level.comment = remove_private_comments(@content)
    @top_level
  end

  def remove_private_comments(comment)
    comment.gsub(/^--\n.*?^\+\+/m, '').sub(/^--\n.*/m, '')
  end

end

