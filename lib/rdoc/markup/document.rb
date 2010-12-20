##
# A Document containing lists, headings, paragraphs, etc.

class RDoc::Markup::Document

  ##
  # The parts of the Document

  attr_reader :parts

  ##
  # Creates a new Document with +parts+

  def initialize *parts
    @parts = []
    @parts.push(*parts)
  end

  ##
  # Appends +part+ to the document

  def << part
    case part
    when RDoc::Markup::Document then
      unless part.empty? then
        parts.push(*part.parts)
        parts << RDoc::Markup::BlankLine.new
      end
    when String then
      raise ArgumentError,
            "expected RDoc::Markup::Document and friends, got String" unless
        part.empty?
    else
      parts << part
    end
  end

  def == other # :nodoc:
    self.class == other.class and @parts == other.parts
  end

  ##
  # Runs this document and all its #items through +visitor+

  def accept visitor
    visitor.start_accepting

    @parts.each do |item|
      item.accept visitor
    end

    visitor.end_accepting
  end

  ##
  # Does this document have no parts?

  def empty?
    @parts.empty?
  end

  def pretty_print q # :nodoc:
    q.group 2, '[doc: ', ']' do
      q.seplist @parts do |part|
        q.pp part
      end
    end
  end

  ##
  # Appends +parts+ to the document

  def push *parts
    self.parts.push(*parts)
  end

end

