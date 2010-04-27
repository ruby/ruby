##
# A Paragraph of text

class RDoc::Markup::Paragraph < RDoc::Markup::Raw

  def accept visitor
    visitor.accept_paragraph self
  end

end

