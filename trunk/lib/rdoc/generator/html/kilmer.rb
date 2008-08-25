require 'rdoc/generator/html'

module RDoc::Generator::HTML::KILMER

  FONTS = "Verdana, Arial, Helvetica, sans-serif"

  STYLE = <<-EOF
body,td,p { font-family: <%= values["fonts"] %>;
       color: #000040;
}

.attr-rw { font-size: xx-small; color: #444488 }

.title-row { background-color: #CCCCFF;
             color:      #000010;
}

.big-title-font {
  color: black;
  font-weight: bold;
  font-family: <%= values["fonts"] %>;
  font-size: large;
  height: 60px;
  padding: 10px 3px 10px 3px;
}

.small-title-font { color: black;
                    font-family: <%= values["fonts"] %>;
                    font-size:10; }

.aqua { color: black }

.method-name, .attr-name {
      font-family: font-family: <%= values["fonts"] %>;
      font-weight: bold;
      font-size: small;
      margin-left: 20px;
      color: #000033;
}

.tablesubtitle, .tablesubsubtitle {
   width: 100%;
   margin-top: 1ex;
   margin-bottom: .5ex;
   padding: 5px 0px 5px 3px;
   font-size: large;
   color: black;
   background-color: #CCCCFF;
   border: thin;
}

.name-list {
  margin-left: 5px;
  margin-bottom: 2ex;
  line-height: 105%;
}

.description {
  margin-left: 5px;
  margin-bottom: 2ex;
  line-height: 105%;
  font-size: small;
}

.methodtitle {
  font-size: small;
  font-weight: bold;
  text-decoration: none;
  color: #000033;
  background-color: white;
}

.srclink {
  font-size: small;
  font-weight: bold;
  text-decoration: none;
  color: #0000DD;
  background-color: white;
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
<body bgcolor="white">

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
<% end %><%# values["requires"] %>
<% end %>
</div>

<% if values["methods"] then %>
<table cellpadding="5" width="100%">
<tr><td class="tablesubtitle">Methods</td></tr>
</table><br />
<div class="name-list">
<% values["methods"].each do |methods| %>
<%= href methods["aref"], methods["name"] %>,
<% end %><%# values["methods"] %>
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
<tr><td class="tablesubtitle">Attributes</td></tr>
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
<tr><td class="tablesubtitle">Classes and Modules</td></tr>
</table><br />
<%= sections["classlist"] %><br />
<% end %>

  <%= template_include %>  <!-- method descriptions -->

<% end %><%# values["sections"] %>

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
  EOF

  METHOD_LIST = <<-EOF
<% if values["includes"] then %>
<div class="tablesubsubtitle">Included modules</div><br />
<div class="name-list">
<% values["includes"].each do |includes| %>
    <span class="method-name"><%= href includes["aref"], includes["name"] %></span>
<% end %><%# values["includes"] %>
</div>
<% end %>

<% if values["method_list"] then %>
<% values["method_list"].each do |method_list| $stderr.puts({ :method_list => method_list }.inspect) %>
<% if values["methods"] then %>
<table cellpadding=5 width="100%">
<tr><td class="tablesubtitle"><%= values["type"] %> <%= values["category"] %> methods</td></tr>
</table>
<% values["methods"].each do |methods| $stderr.puts({ :methods => methods }.inspect) %>
<table width="100%" cellspacing="0" cellpadding="5" border="0">
<tr><td class="methodtitle">
<a name="<%= values["aref"] %>">
<% if values["callseq"] then %>
<b><%= values["callseq"] %></b>
<% end %>
<% unless values["callseq"] then %>
 <b><%= values["name"] %></b><%= values["params"] %>
<% end %>
<% if values["codeurl"] then %>
<a href="<%= values["codeurl"] %>" target="source" class="srclink">src</a>
<% end %>
</a></td></tr>
</table>
<% if values["m_desc"] then %>
<div class="description">
<%= values["m_desc"] %>
</div>
<% end %>
<% if values["aka"] then %>
<div class="aka">
This method is also aliased as
<% values["aka"].each do |aka| $stderr.puts({ :aka => aka }.inspect) %>
<a href="<%= values["aref"] %>"><%= values["name"] %></a>
<% end %><%# values["aka"] %>
</div>
<% end %>
<% if values["sourcecode"] then %>
<pre class="source">
<%= values["sourcecode"] %>
</pre>
<% end %>
<% end %><%# values["methods"] %>
<% end %>
<% end %><%# values["method_list"] %>
<% end %>
  EOF

  SRC_PAGE = <<-EOF
<html>
<head><title><%= values["title"] %></title>
<meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>">
<style type="text/css">
.ruby-comment    { color: green; font-style: italic }
.ruby-constant   { color: #4433aa; font-weight: bold; }
.ruby-identifier { color: #222222;  }
.ruby-ivar       { color: #2233dd; }
.ruby-keyword    { color: #3333FF; font-weight: bold }
.ruby-node       { color: #777777; }
.ruby-operator   { color: #111111;  }
.ruby-regexp     { color: #662222; }
.ruby-value      { color: #662222; font-style: italic }
  .kw { color: #3333FF; font-weight: bold }
  .cmt { color: green; font-style: italic }
  .str { color: #662222; font-style: italic }
  .re  { color: #662222; }
</style>
</head>
<body bgcolor="white">
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
<style>
<!--
body {
  background-color: #ddddff;
  font-family: #{FONTS};
  font-size: 11px;
  font-style: normal;
  line-height: 14px;
  color: #000040;
}

div.banner {
  background: #0000aa;
  color: white;
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
<% end %><%# values["entries"] %>
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
        <frame src="fr_class_index.html"  name="Classes">
        <frame src="fr_method_index.html" name="Methods">
    </frameset>
<% if values["inline_source"] then %>
      <frame  src="<%= values["initial_page"] %>" name="docwin">
<% end %>
<% unless values["inline_source"] then %>
    <frameset rows="80%,20%">
      <frame  src="<%= values["initial_page"] %>" name="docwin">
      <frame  src="blank.html" name="source">
    </frameset>
<% end %>
    <noframes>
          <body bgcolor="white">
            Click <a href="html/index.html">here</a> for a non-frames
            version of this page.
          </body>
    </noframes>
</frameset>

</html>
  EOF

  # A blank page to use as a target
  BLANK = %{
<html><body bgcolor="white"></body></html>
}

  def write_extra_pages
    template = TemplatePage.new(BLANK)
    File.open("blank.html", "w") { |f| template.write_html_on(f, {}) }
  end

end

