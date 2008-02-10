require 'rdoc/markup'

class RDoc::Markup::Formatter

  def initialize
    @markup = RDoc::Markup.new
  end

  def convert(content)
    @markup.convert content, self
  end

end

