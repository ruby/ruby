require 'rdoc/generator/html'
require 'rdoc/generator/html/common'

#
# This class generates Kilmer-style templates.  Right now,
# rdoc is shipped with two such templates:
# * kilmer
# * hefss
#
# Kilmer-style templates use frames.  The left side of the page has
# three frames stacked on top of each other: one lists
# files, one lists classes, and one lists methods.  If source code
# is not inlined, an additional frame runs across the bottom of
# the page and will be used to display method source code.
# The central (and largest frame) display class and file
# pages.
#
# The constructor of this class accepts a Hash containing stylistic
# attributes.  Then, a get_BLAH instance method of this class returns a
# value for the template's BLAH constant.  get_BODY, for instance, returns
# the value of the template's BODY constant.
#
class RDoc::Generator::HTML::KilmerFactory

  include RDoc::Generator::HTML::Common

  #
  # The contents of the stylesheet that should be used for the
  # central frame (for the class and file pages).
  #
  # This must be specified in the Hash passed to the constructor.
  #
  attr_reader :central_css

  #
  # The contents of the stylesheet that should be used for the
  # index pages.
  #
  # This must be specified in the Hash passed to the constructor.
  #
  attr_reader :index_css

  #
  # The heading that should be displayed before listing methods.
  #
  # If not supplied, this defaults to "Methods".
  #
  attr_reader :method_list_heading

  #
  # The heading that should be displayed before listing classes and
  # modules.
  #
  # If not supplied, this defaults to "Classes and Modules".
  #
  attr_reader :class_and_module_list_heading

  #
  # The heading that should be displayed before listing attributes.
  #
  # If not supplied, this defaults to "Attributes".
  #
  attr_reader :attribute_list_heading

  #
  # ====Description:
  # This method constructs a KilmerFactory instance, which
  # can be used to build Kilmer-style template classes.
  # The +style_attributes+ argument is a Hash that contains the
  # values of the classes attributes (Symbols mapped to Strings).
  #
  # ====Parameters:
  # [style_attributes]
  #      A Hash describing the appearance of the Kilmer-style.
  #
  def initialize(style_attributes)
    @central_css = style_attributes[:central_css]
    if(!@central_css)
      raise ArgumentError, "did not specify a value for :central_css"
    end

    @index_css = style_attributes[:index_css]
    if(!@index_css)
      raise ArgumentError, "did not specify a value for :index_css"
    end

    @method_list_heading = style_attributes[:method_list_heading]
    if(!@method_list_heading)
      @method_list_heading = "Methods"
    end

    @class_and_module_list_heading = style_attributes[:class_and_module_list_heading]
    if(!@class_and_module_list_heading)
      @class_and_module_list_heading = "Classes and Modules"
    end

    @attribute_list_heading = style_attributes[:attribute_list_heading]
    if(!@attribute_list_heading)
      @attribute_list_heading = "Attributes"
    end
  end

  def get_STYLE
    return @central_css
  end

  def get_METHOD_LIST
    return %{
<% if values["diagram"] then %>
<div id="diagram">
<table width="100%"><tr><td align="center">
<%= values["diagram"] %>
</td></tr></table>
</div>
<% end %>

<% if values["description"] then %>
<div class="description"><%= values["description"] %></div>
<% end %>

<% if values["requires"] then %>
<table cellpadding="5" width="100%">
<tr><td class="tablesubtitle">Required files</td></tr>
</table><br />
<div class="name-list">
<% values["requires"].each do |requires| %>
<%= href requires["aref"], requires["name"] %>
<% end %><%# values["requires"] %>
</div>
<% end %>

<% if values["methods"] then %>
<table cellpadding="5" width="100%">
<tr><td class="tablesubtitle">#{@method_list_heading}</td></tr>
</table><br />
<div class="name-list">
<% values["methods"].each do |methods| %>
<%= href methods["aref"], methods["name"] %>,
<% end %><%# values["methods"] %>
</div>
<% end %>

<% if values["includes"] then %>
<div class="tablesubsubtitle">Included modules</div><br />
<div class="name-list">
<% values["includes"].each do |includes| %>
    <span class="method-name"><%= href includes["aref"], includes["name"] %></span>
<% end %><%# values["includes"] %>
</div>
<% end %>

<% values["sections"].each do |sections| %>
    <div id="section">
<% if sections["sectitle"] then %>
      <h2 class="section-title"><a name="<%= sections["secsequence"] %>"><%= sections["sectitle"] %></a></h2>
<% if sections["seccomment"] then %>
      <div class="section-comment">
        <%= sections["seccomment"] %>
      </div>
<% end %>
<% end %>
<% if sections["attributes"] then %>
<table cellpadding="5" width="100%">
<tr><td class="tablesubtitle">#{@attribute_list_heading}</td></tr>
</table><br />
<table cellspacing="5">
<% sections["attributes"].each do |attributes| %>
     <tr valign="top">
<% if attributes["rw"] then %>
       <td align="center" class="attr-rw">&nbsp;[<%= attributes["rw"] %>]&nbsp;</td>
<% end %>
<% unless attributes["rw"] then %>
       <td></td>
<% end %>
       <td class="attr-name"><%= attributes["name"] %></td>
       <td><%= attributes["a_desc"] %></td>
     </tr>
<% end %><%# sections["attributes"] %>
</table>
<% end %>

<% if sections["classlist"] then %>
<table cellpadding="5" width="100%">
<tr><td class="tablesubtitle">#{@class_and_module_list_heading}</td></tr>
</table><br />
<%= sections["classlist"] %><br />
<% end %>

<% if sections["method_list"] then %>
<% sections["method_list"].each do |method_list| %>
<% if method_list["methods"] then %>
<table cellpadding="5" width="100%">
<tr><td class="tablesubtitle"><%= method_list["type"] %> <%= method_list["category"] %> methods</td></tr>
</table>
<% method_list["methods"].each do |methods| %>
<table width="100%" cellspacing="0" cellpadding="5" border="0">
<tr><td class="methodtitle">
<a name="<%= methods["aref"] %>">
<% if methods["callseq"] then %>
<b><%= methods["callseq"] %></b>
<% end %>
<% unless methods["callseq"] then %>
 <b><%= methods["name"] %></b><%= methods["params"] %>
<% end %>
</a>
<% if methods["codeurl"] then %>
<a href="<%= methods["codeurl"] %>" target="source" class="srclink">src</a>
<% end %>
</td></tr>
</table>
<% if methods["m_desc"] then %>
<div class="description">
<%= methods["m_desc"] %>
</div>
<% end %>
<% if methods["aka"] then %>
<div class="aka">
This method is also aliased as
<% methods["aka"].each do |aka| %>
<a href="<%= methods["aref"] %>"><%= methods["name"] %></a>
<% end %><%# methods["aka"] %>
</div>
<% end %>
<% if methods["sourcecode"] then %>
<pre class="source">
<%= methods["sourcecode"] %>
</pre>
<% end %>
<% end %><%# method_list["methods"] %>
<% end %>
<% end %><%# sections["method_list"] %>
<% end %>

<% end %><%# values["sections"] %>
</div>
}
  end

  def get_BODY
    return XHTML_STRICT_PREAMBLE + HTML_ELEMENT + %{
<head>
  <title><%= values["title"] %></title>
  <meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>" />
  <link rel="stylesheet" href="<%= values["style_url"] %>" type="text/css" media="screen" />
  <script type="text/javascript">
  <!--
  function popCode(url) {
    parent.frames.source.location = url
  }
  //-->
  </script>
</head>
<body>
<div class="bodyContent">
<%= template_include %>  <!-- banner header -->

#{get_METHOD_LIST()}
</div>
</body>
</html>
}
  end

def get_FILE_PAGE
  return %{
<table width="100%">
 <tr class="title-row">
 <td><table width="100%"><tr>
   <td class="big-title-font" colspan="2">File<br /><%= values["short_name"] %></td>
   <td align="right"><table cellspacing="0" cellpadding="2">
         <tr>
           <td class="small-title-font">Path:</td>
           <td class="small-title-font"><%= values["full_path"] %>
<% if values["cvsurl"] then %>
				&nbsp;(<a href="<%= values["cvsurl"] %>"><acronym title="Concurrent Versioning System">CVS</acronym></a>)
<% end %>
           </td>
         </tr>
         <tr>
           <td class="small-title-font">Modified:</td>
           <td class="small-title-font"><%= values["dtm_modified"] %></td>
         </tr>
        </table>
    </td></tr></table></td>
  </tr>
</table><br />
}
end

def get_CLASS_PAGE
  return %{
<table width="100%" border="0" cellspacing="0">
 <tr class="title-row">
 <td class="big-title-font">
   <%= values["classmod"] %><br /><%= values["full_name"] %>
 </td>
 <td align="right">
   <table cellspacing="0" cellpadding="2">
     <tr valign="top">
      <td class="small-title-font">In:</td>
      <td class="small-title-font">
<% values["infiles"].each do |infiles| %>
<%= href infiles["full_path_url"], infiles["full_path"] %>
<% if infiles["cvsurl"] then %>
&nbsp;(<a href="<%= infiles["cvsurl"] %>"><acronym title="Concurrent Versioning System">CVS</acronym></a>)
<% end %>
<% end %><%# values["infiles"] %>
      </td>
     </tr>
<% if values["parent"] then %>
     <tr>
      <td class="small-title-font">Parent:</td>
      <td class="small-title-font">
<% if values["par_url"] then %>
        <a href="<%= values["par_url"] %>" class="cyan">
<% end %>
<%= values["parent"] %>
<% if values["par_url"] then %>
         </a>
<% end %>
      </td>
     </tr>
<% end %>
   </table>
  </td>
  </tr>
</table><br />
}
end

def get_SRC_PAGE
  return XHTML_STRICT_PREAMBLE + HTML_ELEMENT + %{
<head><title><%= values["title"] %></title>
<meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>" />
<link rel="stylesheet" href="<%= values["style_url"] %>" type="text/css" media="screen" />
</head>
<body>
<pre><%= values["code"] %></pre>
</body>
</html>
}
end

def get_FR_INDEX_BODY
  return %{<%= template_include %>}
end

def get_FILE_INDEX
  return XHTML_STRICT_PREAMBLE + HTML_ELEMENT + %{
<head>
<title><%= values["title"] %></title>
<meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>" />
<style type="text/css">
<!--
#{@index_css}
-->
</style>
<base target="docwin" />
</head>
<body>
<div class="index">
<div class="banner"><%= values["list_title"] %></div>
<% values["entries"].each do |entries| %>
<a href="<%= entries["href"] %>"><%= entries["name"] %></a><br />
<% end %><%# values["entries"] %>
</div>
</body></html>
}
end

def get_CLASS_INDEX
  return get_FILE_INDEX
end

def get_METHOD_INDEX
  return get_FILE_INDEX
end

def get_INDEX
  return XHTML_FRAME_PREAMBLE + HTML_ELEMENT + %{
<head>
  <title><%= values["title"] %></title>
  <meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>" />
</head>

<frameset cols="20%,*">
    <frameset rows="15%,35%,50%">
        <frame src="fr_file_index.html"   title="Files" name="Files" />
        <frame src="fr_class_index.html"  name="Classes" />
        <frame src="fr_method_index.html" name="Methods" />
    </frameset>
<% if values["inline_source"] then %>
      <frame  src="<%= values["initial_page"] %>" name="docwin" />
<% end %>
<% unless values["inline_source"] then %>
    <frameset rows="80%,20%">
      <frame  src="<%= values["initial_page"] %>" name="docwin" />
      <frame  src="blank.html" name="source" />
    </frameset>
<% end %>
</frameset>

</html>
}
end

def get_BLANK
  # This will be displayed in the source code frame before
  # any source code has been selected.
  return XHTML_STRICT_PREAMBLE + HTML_ELEMENT + %{
<head>
  <title>Source Code Frame <%= values["title_suffix"] %></title>
  <meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>" />
  <link rel="stylesheet" href="<%= values["style_url"] %>" type="text/css" media="screen" />
</head>
<body>
</body>
</html>
}
end

def write_extra_pages(values)
  template = RDoc::TemplatePage.new(get_BLANK())
  File.open("blank.html", "w") { |f| template.write_html_on(f, values) }
end

end
