require 'rdoc/markup'
require 'rdoc/markup/formatter'

##
# This Markup outputter is used for testing purposes.

class RDoc::Markup::ToTest < RDoc::Markup::Formatter

  ##
  # :section: Visitor

  def start_accepting
    @res = []
    @list = []
  end

  def end_accepting
    @res
  end

  def accept_paragraph(paragraph)
    @res << paragraph.text
  end

  def accept_verbatim(verbatim)
    @res << verbatim.text
  end

  def accept_list_start(list)
    @list << case list.type
             when :BULLET then
               '*'
             when :NUMBER then
               '1'
             else
               list.type
             end
  end

  def accept_list_end(list)
    @list.pop
  end

  def accept_list_item_start(list_item)
    @res << "#{' ' * (@list.size - 1)}#{@list.last}: "
  end

  def accept_list_item_end(list_item)
  end

  def accept_blank_line(blank_line)
    @res << "\n"
  end

  def accept_heading(heading)
    @res << "#{'=' * heading.level} #{heading.text}"
  end

  def accept_rule(rule)
    @res << '-' * rule.weight
  end

end

