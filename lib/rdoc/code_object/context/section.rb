# frozen_string_literal: true
require 'cgi/escape'

##
# A section of documentation like:
#
#   # :section: The title
#   # The body
#
# Sections can be referenced multiple times and will be collapsed into a
# single section.

class RDoc::Context::Section

  include RDoc::Text

  MARSHAL_VERSION = 0 # :nodoc:

  ##
  # Section comment

  attr_reader :comment

  ##
  # Section comments

  attr_reader :comments

  ##
  # Context this Section lives in

  attr_reader :parent

  ##
  # Section title

  attr_reader :title

  ##
  # Creates a new section with +title+ and +comment+

  def initialize(parent, title, comment)
    @parent = parent
    @title = title ? title.strip : title

    @comments = []

    add_comment comment
  end

  ##
  # Sections are equal when they have the same #title

  def ==(other)
    self.class === other and @title == other.title
  end

  alias eql? ==

  ##
  # Adds +comment+ to this section

  def add_comment(comment)
    comments = Array(comment)
    comments.each do |c|
      extracted_comment = extract_comment(c)
      @comments << extracted_comment unless extracted_comment.empty?
    end
  end

  ##
  # Anchor reference for linking to this section

  def aref
    title = @title || '[untitled]'

    CGI.escape(title).gsub('%', '-').sub(/^-/, '')
  end

  ##
  # Extracts the comment for this section from the original comment block.
  # If the first line contains :section:, strip it and use the rest.
  # Otherwise remove lines up to the line containing :section:, and look
  # for those lines again at the end and remove them. This lets us write
  #
  #   # :section: The title
  #   # The body

  def extract_comment(comment)
    case comment
    when nil
      RDoc::Comment.new ''
    when RDoc::Comment then
      if comment.text =~ /^#[ \t]*:section:.*\n/ then
        start = $`
        rest = $'

        comment.text = if start.empty? then
                         rest
                       else
                         rest.sub(/#{start.chomp}\Z/, '')
                       end
      end

      comment
    else
      raise TypeError, "unknown comment #{comment.inspect}"
    end
  end

  def inspect # :nodoc:
    "#<%s:0x%x %p>" % [self.class, object_id, title]
  end

  def hash # :nodoc:
    @title.hash
  end

  ##
  # The files comments in this section come from

  def in_files
    @comments.map(&:file)
  end

  ##
  # Serializes this Section.  The title and parsed comment are saved, but not
  # the section parent which must be restored manually.

  def marshal_dump
    [
      MARSHAL_VERSION,
      @title,
      parse,
    ]
  end

  ##
  # De-serializes this Section.  The section parent must be restored manually.

  def marshal_load(array)
    @parent  = nil

    @title    = array[1]
    @comments = array[2].parts.map { |doc| RDoc::Comment.from_document(doc) }
  end

  ##
  # Parses +comment_location+ into an RDoc::Markup::Document composed of
  # multiple RDoc::Markup::Documents with their file set.

  def parse
    RDoc::Markup::Document.new(*@comments.map(&:parse))
  end

  ##
  # The section's title, or 'Top Section' if the title is nil.
  #
  # This is used by the table of contents template so the name is silly.

  def plain_html
    @title || 'Top Section'
  end

  ##
  # Removes a comment from this section if it is from the same file as
  # +comment+

  def remove_comment(target_comment)
    @comments.delete_if do |stored_comment|
      stored_comment.file == target_comment.file
    end
  end

end
