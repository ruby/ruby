require 'rdoc/generator/html'
require 'rdoc/generator/html/html'

module RDoc::Generator::HTML::HEFSS

  FONTS = "Verdana, Arial, Helvetica, sans-serif"

STYLE = <<-EOF
body,p { font-family: Verdana, Arial, Helvetica, sans-serif;
       color: #000040; background: #BBBBBB;
}

td { font-family: Verdana, Arial, Helvetica, sans-serif;
       color: #000040;
}

.attr-rw { font-size: small; color: #444488 }

.title-row {color:      #eeeeff;
	    background: #BBBBDD;
}

.big-title-font { color: white;
                  font-family: Verdana, Arial, Helvetica, sans-serif;
                  font-size: large;
                  height: 50px}

.small-title-font { color: purple;
                    font-family: Verdana, Arial, Helvetica, sans-serif;
                    font-size: small; }

.aqua { color: purple }

.method-name, attr-name {
      font-family: monospace; font-weight: bold;
}

.tablesubtitle {
   width: 100%;
   margin-top: 1ex;
   margin-bottom: .5ex;
   padding: 5px 0px 5px 20px;
   font-size: large;
   color: purple;
   background: #BBBBCC;
}

.tablesubsubtitle {
   width: 100%;
   margin-top: 1ex;
   margin-bottom: .5ex;
   padding: 5px 0px 5px 20px;
   font-size: medium;
   color: white;
   background: #BBBBCC;
}

.name-list {
  font-family: monospace;
  margin-left: 40px;
  margin-bottom: 2ex;
  line-height: 140%;
}

.description {
  margin-left: 40px;
  margin-bottom: 2ex;
  line-height: 140%;
}

.methodtitle {
  font-size: medium;
  text_decoration: none;
  padding: 3px 3px 3px 20px;
  color: #0000AA;
}

.column-title {
  font-size: medium;
  font-weight: bold;
  text_decoration: none;
  padding: 3px 3px 3px 20px;
  color: #3333CC;
  }

.variable-name {
  font-family: monospace;
  font-size: medium;
  text_decoration: none;
  padding: 3px 3px 3px 20px;
  color: #0000AA;
}

.row-name {
  font-size: medium;
  font-weight: medium;
  font-family: monospace;
  text_decoration: none;
  padding: 3px 3px 3px 20px;
}

.paramsig {
   font-size: small;
}

.srcbut { float: right }

  EOF

  BODY = <<-EOF
<html><head>
  <title><%= values["title"] %></title>
  <meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>">
  <link rel="stylesheet" href="<%= values["style_url"] %>" type="text/css" media="screen" />
  <script type="text/javascript" language="JavaScript">
  <!--
  function popCode(url) {
    parent.frames.source.location = url
  }
  //-->
  </script>
</head>
<body bgcolor="#BBBBBB">

<%= template_include %>  <!-- banner header -->

<% if values["diagram"] then %>
<table width="100%"><tr><td align="center">
<%= values["diagram"] %>
</td></tr></table>
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
<% end # values["requires"] %>
<% end %>
</div>

<% if values["sections"] then %>
<% values["sections"].each do |sections| %>
<% if sections["method_list"] then %>
<% sections["method_list"].each do |method_list| %>
<% if method_list["methods"] then %>
<table cellpadding="5" width="100%">
<tr><td class="tablesubtitle">Subroutines and Functions</td></tr>
</table><br />
<div class="name-list">
<% method_list["methods"].each do |methods| %>
<a href="<%= methods["codeurl"] %>" target="source"><%= methods["name"] %></a>
<% end # values["methods"] %>
</div>
<% end %>
<% end # values["method_list"] %>
<% end %>

<% if sections["attributes"] then %>
<table cellpadding="5" width="100%">
<tr><td class="tablesubtitle">Arguments</td></tr>
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
<% end # values["attributes"] %>
</table>
<% end %>
<% end # values["sections"] %>
<% end %>

<% if values["classlist"] then %>
<table cellpadding="5" width="100%">
<tr><td class="tablesubtitle">Modules</td></tr>
</table><br />
<%= values["classlist"] %><br />
<% end %>

  <%= template_include %>  <!-- method descriptions -->

</body>
</html>
  EOF

  FILE_PAGE = <<-EOF
<table width="100%">
 <tr class="title-row">
 <td><table width="100%"><tr>
   <td class="big-title-font" colspan="2"><font size="-3"><b>File</b><br /></font><%= values["short_name"] %></td>
   <td align="right"><table cellspacing="0" cellpadding="2">
         <tr>
           <td  class="small-title-font">Path:</td>
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
  EOF

  CLASS_PAGE = <<-EOF
<table width="100%" border="0" cellspacing="0">
 <tr class="title-row">
 <td class="big-title-font">
   <font size="-3"><b><%= values["classmod"] %></b><br /></font><%= values["full_name"] %>
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
<% end # values["infiles"] %>
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
  EOF

  METHOD_LIST = <<-EOF
<% if values["includes"] then %>
<div class="tablesubsubtitle">Uses</div><br />
<div class="name-list">
<% values["includes"].each do |includes| %>
    <span class="method-name"><%= href includes["aref"], includes["name"] %></span>
<% end # values["includes"] %>
</div>
<% end %>

<% if values["sections"] then %>
<% values["sections"].each do |sections| %>
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
<b><%= methods["name"] %></b><%= methods["params"] %>
<% if methods["codeurl"] then %>
<a href="<%= methods["codeurl"] %>" target="source" class="srclink">src</a>
<% end %>
</a></td></tr>
</table>
<% if method_list["m_desc"] then %>
<div class="description">
<%= method_list["m_desc"] %>
</div>
<% end %>
<% end # method_list["methods"] %>
<% end %>
<% end # sections["method_list"] %>
<% end %>
<% end # values["sections"] %>
<% end %>
  EOF

  SRC_PAGE = <<-EOF
<html>
<head><title><%= values["title"] %></title>
<meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>">
<style type="text/css">
  .kw { color: #3333FF; font-weight: bold }
  .cmt { color: green; font-style: italic }
  .str { color: #662222; font-style: italic }
  .re  { color: #662222; }
.ruby-comment    { color: green; font-style: italic }
.ruby-constant   { color: #4433aa; font-weight: bold; }
.ruby-identifier { color: #222222;  }
.ruby-ivar       { color: #2233dd; }
.ruby-keyword    { color: #3333FF; font-weight: bold }
.ruby-node       { color: #777777; }
.ruby-operator   { color: #111111;  }
.ruby-regexp     { color: #662222; }
.ruby-value      { color: #662222; font-style: italic }
</style>
</head>
<body bgcolor="#BBBBBB">
<pre><%= values["code"] %></pre>
</body>
</html>
  EOF

  FR_INDEX_BODY = %{
<%= template_include %>
}

  FILE_INDEX = <<-EOF
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>">
<style type="text/css">
<!--
  body {
background-color: #bbbbbb;
     font-family: #{FONTS};
       font-size: 11px;
      font-style: normal;
     line-height: 14px;
           color: #000040;
  }
div.banner {
  background: #bbbbcc;
  color:      white;
  padding: 1;
  margin: 0;
  font-size: 90%;
  font-weight: bold;
  line-height: 1.1;
  text-align: center;
  width: 100%;
}

-->
</style>
<base target="docwin">
</head>
<body>
<div class="banner"><%= values["list_title"] %></div>
<% values["entries"].each do |entries| %>
<a href="<%= entries["href"] %>"><%= entries["name"] %></a><br />
<% end # values["entries"] %>
</body></html>
  EOF

  CLASS_INDEX = FILE_INDEX
  METHOD_INDEX = FILE_INDEX

  INDEX = <<-EOF
<html>
<head>
  <title><%= values["title"] %></title>
  <meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>">
</head>

<frameset cols="20%,*">
    <frameset rows="15%,35%,50%">
        <frame src="fr_file_index.html"   title="Files" name="Files">
        <frame src="fr_class_index.html"  name="Modules">
        <frame src="fr_method_index.html" name="Subroutines and Functions">
    </frameset>
    <frameset rows="80%,20%">
      <frame  src="<%= values["initial_page"] %>" name="docwin">
      <frame  src="blank.html" name="source">
    </frameset>
    <noframes>
          <body bgcolor="#BBBBBB">
            Click <a href="html/index.html">here</a> for a non-frames
            version of this page.
          </body>
    </noframes>
</frameset>

</html>
  EOF

  # Blank page to use as a target
  BLANK = %{
<html><body bgcolor="#BBBBBB"></body></html>
}

  def write_extra_pages
    template = TemplatePage.new(BLANK)
    File.open("blank.html", "w") { |f| template.write_html_on(f, {}) }
  end

end

