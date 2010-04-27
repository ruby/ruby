##
# A section of verbatim text

class RDoc::Markup::Verbatim < RDoc::Markup::Raw

  def accept visitor
    visitor.accept_verbatim self
  end

  ##
  # Collapses 3+ newlines into two newlines

  def normalize
    parts = []

    newlines = 0

    @parts.each do |part|
      case part
      when /\n/ then
        newlines += 1
        parts << part if newlines <= 2
      else
        newlines = 0
        parts << part
      end
    end

    parts.slice!(-1) if parts[-2..-1] == ["\n", "\n"]

    @parts = parts
  end

  ##
  # The text of the section

  def text
    @parts.join
  end

end

