##
# A Paragraph of text

class RDoc::Markup::Paragraph

  ##
  # The component parts of the list

  attr_reader :parts

  ##
  # Creates a new Paragraph containing +parts+

  def initialize *parts
    @parts = []
    @parts.push(*parts)
  end

  ##
  # Appends +text+ to the Paragraph

  def << text
    @parts << text
  end

  def == other # :nodoc:
    self.class == other.class and text == other.text
  end

  def accept visitor
    visitor.accept_paragraph self
  end

  ##
  # Appends +other+'s parts into this Paragraph

  def merge other
    @parts.push(*other.parts)
  end

  def pretty_print q # :nodoc:
    self.class.name =~ /.*::(\w{4})/i

    q.group 2, "[#{$1.downcase}: ", ']' do
      q.seplist @parts do |part|
        q.pp part
      end
    end
  end

  ##
  # Appends +texts+ onto this Paragraph

  def push *texts
    self.parts.push(*texts)
  end

  ##
  # The text of this paragraph

  def text
    @parts.join ' '
  end

end

