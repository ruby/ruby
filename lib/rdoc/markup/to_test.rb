require 'rdoc/markup'

##
# This Markup outputter is used for testing purposes.

class RDoc::Markup::ToTest

  def start_accepting
    @res = []
  end

  def end_accepting
    @res
  end

  def accept_paragraph(am, fragment)
    @res << fragment.to_s
  end

  def accept_verbatim(am, fragment)
    @res << fragment.to_s
  end

  def accept_list_start(am, fragment)
    @res << fragment.to_s
  end

  def accept_list_end(am, fragment)
    @res << fragment.to_s
  end

  def accept_list_item(am, fragment)
    @res << fragment.to_s
  end

  def accept_blank_line(am, fragment)
    @res << fragment.to_s
  end

  def accept_heading(am, fragment)
    @res << fragment.to_s
  end

  def accept_rule(am, fragment)
    @res << fragment.to_s
  end

end

