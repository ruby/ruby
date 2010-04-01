##
# An empty line

class RDoc::Markup::BlankLine

  def == other # :nodoc:
    self.class == other.class
  end

  def accept visitor
    visitor.accept_blank_line self
  end

  def pretty_print q # :nodoc:
    q.text 'blankline'
  end

end

