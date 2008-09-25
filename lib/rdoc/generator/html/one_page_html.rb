require 'rdoc/generator/html'
require 'rdoc/generator/html/common'

module RDoc::Generator::HTML::ONE_PAGE_HTML

  include RDoc::Generator::HTML::Common

  CONTENTS_XML = <<-EOF
<% if defined? classes and classes["description"] then %>
<%= classes["description"] %>
<% end %>

<% if defined? files and files["requires"] then %>
<h4>Requires:</h4>
<ul>
<% files["requires"].each do |requires| %>
<% if requires["aref"] then %>
<li><a href="<%= requires["aref"] %>"><%= requires["name"] %></a></li>
<% end %>
<% unless requires["aref"] then %>
<li><%= requires["name"] %></li>
<% end %>
<% end %><%# files["requires"] %>
</ul>
<% end %>

<% if defined? classes and classes["includes"] then %>
<h4>Includes</h4>
<ul>
<% classes["includes"].each do |includes| %>
<% if includes["aref"] then %>
<li><a href="<%= includes["aref"] %>"><%= includes["name"] %></a></li>
<% end %>
<% unless includes["aref"] then %>
<li><%= includes["name"] %></li>
<% end %>
<% end %><%# classes["includes"] %>
</ul>
<% end %>

<% if defined? classes and classes["sections"] then %>
<% classes["sections"].each do |sections| %>
<% if sections["attributes"] then %>
<h4>Attributes</h4>
<table>
<% sections["attributes"].each do |attributes| %>
<tr><td><%= attributes["name"] %></td><td><%= attributes["rw"] %></td><td><%= attributes["a_desc"] %></td></tr>
<% end %><%# sections["attributes"] %>
</table>
<% end %>

<% if sections["method_list"] then %>
<h3>Methods</h3>
<% sections["method_list"].each do |method_list| %>
<% if method_list["methods"] then %>
<% method_list["methods"].each do |methods| %>
<h4><%= methods["type"] %> <%= methods["category"] %> method: 
<% if methods["callseq"] then %>
<a name="<%= methods["aref"] %>"><%= methods["callseq"] %></a>
<% end %>
<% unless methods["callseq"] then %>
<a name="<%= methods["aref"] %>"><%= methods["name"] %><%= methods["params"] %></a></h4>
<% end %>

<% if methods["m_desc"] then %>
<%= methods["m_desc"] %>
<% end %>

<% if methods["sourcecode"] then %>
<blockquote><pre>
<%= methods["sourcecode"] %>
</pre></blockquote>
<% end %>
<% end %><%# method_list["methods"] %>
<% end %>
<% end %><%# sections["method_list"] %>
<% end %>
<% end %><%# classes["sections"] %>
<% end %>
  EOF

  ONE_PAGE = XHTML_STRICT_PREAMBLE + HTML_ELEMENT + %{
<head>
  <title><%= values["title"] %></title>
  <meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>" />
</head>
<body>
<% values["files"].each do |files| %>
<h2>File: <a name="<%= files["href"] %>"><%= files["short_name"] %></a></h2>
<table>
  <tr><td>Path:</td><td><%= files["full_path"] %></td></tr>
  <tr><td>Modified:</td><td><%= files["dtm_modified"] %></td></tr>
</table>
} + CONTENTS_XML + %{
<% end %><%# values["files"] %>

<% if values["classes"] then %>
<h2>Classes</h2>
<% values["classes"].each do |classes| %>
<% if classes["parent"] then %>
<h3><%= classes["classmod"] %> <a name="<%= classes["href"] %>"><%= classes["full_name"] %></a> &lt; <%= href classes["par_url"], classes["parent"] %></h3>
<% end %>
<% unless classes["parent"] then %>
<h3><%= classes["classmod"] %> <%= classes["full_name"] %></h3>
<% end %>

<% if classes["infiles"] then %>
(in files
<% classes["infiles"].each do |infiles| %>
<%= href infiles["full_path_url"], infiles["full_path"] %>
<% end %><%# classes["infiles"] %>
)
<% end %>
} + CONTENTS_XML + %{
<% end %><%# values["classes"] %>
<% end %>
</body>
</html>
}

end

