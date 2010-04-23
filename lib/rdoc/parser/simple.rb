##
# Parse a non-source file. We basically take the whole thing as one big
# comment. If the first character in the file is '#', we strip leading pound
# signs.

class RDoc::Parser::Simple < RDoc::Parser

  parse_files_matching(//)

  attr_reader :content # :nodoc:

  ##
  # Prepare to parse a plain file

  def initialize(top_level, file_name, content, options, stats)
    super

    preprocess = RDoc::Markup::PreProcess.new @file_name, @options.rdoc_include

    preprocess.handle @content do |directive, param|
      top_level.metadata[directive] = param
      false
    end
  end

  ##
  # Extract the file contents and attach them to the TopLevel as a comment

  def scan
    comment = remove_coding_comment @content
    comment = remove_private_comments comment

    @top_level.comment = comment
    @top_level.parser = self.class
    @top_level
  end

  def remove_private_comments(comment)
    comment.gsub(/^--\n.*?^\+\+/m, '').sub(/^--\n.*/m, '')
  end

  def remove_coding_comment text
    text.sub(/\A# .*coding[=:].*$/, '')
  end

end

