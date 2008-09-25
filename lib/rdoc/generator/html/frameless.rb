require 'rdoc/generator/html/html'

##
# = CSS2 RDoc HTML template
#
# This is a template for RDoc that uses XHTML 1.0 Strict and dictates a
# bit more of the appearance of the output to cascading stylesheets than the
# default. It was designed for clean inline code display, and uses DHTMl to
# toggle the visbility of each method's source with each click on the '[source]'
# link.
#
# Frameless basically is the html template without frames.
#
# == Authors
#
# * Michael Granger <ged@FaerieMUD.org>
#
# Copyright (c) 2002, 2003 The FaerieMUD Consortium. Some rights reserved.
#
# This work is licensed under the Creative Commons Attribution License. To view
# a copy of this license, visit http://creativecommons.org/licenses/by/1.0/ or
# send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California
# 94305, USA.

module RDoc::Generator::HTML::FRAMELESS

  FRAMELESS = true

  FONTS = RDoc::Generator::HTML::HTML::FONTS

  STYLE = RDoc::Generator::HTML::HTML::STYLE

  HEADER = RDoc::Generator::HTML::HTML::HEADER

  FOOTER = <<-EOF
  <div id="popupmenu" class="index">
    <br />
    <h1 class="index-entries section-bar">Files</h1>
      <ul>
<% values["file_list"].each do |file| %>
        <li><a href="<%= file["href"] %>"><%= file["name"] %></a></li>
<% end %>
      </ul>

    <br />
    <h1 class="index-entries section-bar">Classes</h1>
      <ul>
<% values["class_list"].each do |klass| %>
        <li><a href="<%= klass["href"] %>"><%= klass["name"] %></a></li>
<% end %>
      </ul>

    <br />
    <h1 class="index-entries section-bar">Methods</h1>
      <ul>
<% values["method_list"].each do |method| %>
        <li><a href="<%= method["href"] %>"><%= method["name"] %></a></li>
<% end %>
      </ul>
  </div>
</body>
</html>
  EOF

  FILE_PAGE = RDoc::Generator::HTML::HTML::FILE_PAGE

  CLASS_PAGE = RDoc::Generator::HTML::HTML::CLASS_PAGE

  METHOD_LIST = RDoc::Generator::HTML::HTML::METHOD_LIST

  BODY = HEADER + %{

<%= template_include %>  <!-- banner header -->

  <div id="bodyContent">

} +  METHOD_LIST + %{

  </div>

} + FOOTER

  SRC_PAGE = RDoc::Generator::HTML::HTML::SRC_PAGE

  FR_INDEX_BODY = RDoc::Generator::HTML::HTML::FR_INDEX_BODY

  FILE_INDEX = RDoc::Generator::HTML::HTML::FILE_INDEX

  CLASS_INDEX = RDoc::Generator::HTML::HTML::CLASS_INDEX

  METHOD_INDEX = RDoc::Generator::HTML::HTML::METHOD_INDEX
end
