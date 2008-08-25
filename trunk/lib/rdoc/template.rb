require 'erb'

module RDoc; end

##
# An ERb wrapper that allows nesting of one ERb template inside another.
#
# This TemplatePage operates similarly to RDoc 1.x's TemplatePage, but uses
# ERb instead of a custom template language.
#
# Converting from a RDoc 1.x template to an RDoc 2.x template is fairly easy.
#
# * %blah% becomes <%= values["blah"] %>
# * !INCLUDE! becomes <%= template_include %>
# * HREF:aref:name becomes <%= href values["aref"], values["name"] %>
# * IF:blah becomes <% if values["blah"] then %>
# * IFNOT:blah becomes <% unless values["blah"] then %>
# * ENDIF:blah becomes <% end %>
# * START:blah becomes <% values["blah"].each do |blah| %>
# * END:blah becomes <% end %>
#
# To make nested loops easier to convert, start by converting START statements
# to:
#
#   <% values["blah"].each do |blah| $stderr.puts blah.keys %>
#
# So you can see what is being used inside which loop.

class RDoc::TemplatePage

  ##
  # Create a new TemplatePage that will use +templates+.

  def initialize(*templates)
    @templates = templates
  end

  ##
  # Returns "<a href=\"#{ref}\">#{name}</a>"

  def href(ref, name)
    if ref then
      "<a href=\"#{ref}\">#{name}</a>"
    else
      name
    end
  end

  ##
  # Process the template using +values+, writing the result to +io+.

  def write_html_on(io, values)
    b = binding
    template_include = ""

    @templates.reverse_each do |template|
      template_include = ERB.new(template).result b
    end

    io.write template_include
  end

end

