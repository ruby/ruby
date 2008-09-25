require 'rdoc/generator/html'
require 'rdoc/generator/html/common'

##
# = CSS2 RDoc HTML template
#
# This is a template for RDoc that uses XHTML 1.0 Strict and dictates a
# bit more of the appearance of the output to cascading stylesheets than the
# default. It was designed for clean inline code display, and uses DHTMl to
# toggle the visibility of each method's source with each click on the
# '[source]' link.
#
# This template *also* forms the basis of the frameless template.
# 
# == Authors
#
# * Michael Granger <ged@FaerieMUD.org>
#
# Copyright (c) 2002, 2003 The FaerieMUD Consortium. Some rights reserved.
#
# This work is licensed under the Creative Commons Attribution License. To
# view a copy of this license, visit
# http://creativecommons.org/licenses/by/1.0/ or send a letter to Creative
# Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

module RDoc::Generator::HTML::HTML

  include RDoc::Generator::HTML::Common

  FONTS = "Verdana,Arial,Helvetica,sans-serif"

  STYLE = <<-EOF
body {
  font-family: #{FONTS};
  font-size: 90%;
  margin: 0;
  margin-left: 40px;
  padding: 0;
  background: white;
  color: black;
}

h1, h2, h3, h4 {
  margin: 0;
  background: transparent;
}

h1 {
  font-size: 150%;
}

h2,h3,h4 {
  margin-top: 1em;
}

:link, :visited {
  background: #eef;
  color: #039;
  text-decoration: none;
}

:link:hover, :visited:hover {
  background: #039;
  color: #eef;
}

/* Override the base stylesheet's Anchor inside a table cell */
td > :link, td > :visited {
  background: transparent;
  color: #039;
  text-decoration: none;
}

/* and inside a section title */
.section-title > :link, .section-title > :visited {
  background: transparent;
  color: #eee;
  text-decoration: none;
}

/* === Structural elements =================================== */

.index {
  margin: 0;
  margin-left: -40px;
  padding: 0;
  font-size: 90%;
}

.index :link, .index :visited {
  margin-left: 0.7em;
}

.index .section-bar {
  margin-left: 0px;
  padding-left: 0.7em;
  background: #ccc;
  font-size: small;
}

#classHeader, #fileHeader {
  width: auto;
  color: white;
  padding: 0.5em 1.5em 0.5em 1.5em;
  margin: 0;
  margin-left: -40px;
  border-bottom: 3px solid #006;
}

#classHeader :link, #fileHeader :link,
#classHeader :visited, #fileHeader :visited {
  background: inherit;
  color: white;
}

#classHeader td, #fileHeader td {
  background: inherit;
  color: white;
}

#fileHeader {
  background: #057;
}

#classHeader {
  background: #048;
}

.class-name-in-header {
  font-size:  180%;
  font-weight: bold;
}

#bodyContent {
  padding: 0 1.5em 0 1.5em;
}

#description {
  padding: 0.5em 1.5em;
  background: #efefef;
  border: 1px dotted #999;
}

#description h1, #description h2, #description h3,
#description h4, #description h5, #description h6 {
  color: #125;
  background: transparent;
}

#validator-badges {
  text-align: center;
}

#validator-badges img {
  border: 0;
}

#copyright {
  color: #333;
  background: #efefef;
  font: 0.75em sans-serif;
  margin-top: 5em;
  margin-bottom: 0;
  padding: 0.5em 2em;
}

/* === Classes =================================== */

table.header-table {
  color: white;
  font-size: small;
}

.type-note {
  font-size: small;
  color: #dedede;
}

.section-bar {
  color: #333;
  border-bottom: 1px solid #999;
  margin-left: -20px;
}

.section-title {
  background: #79a;
  color: #eee;
  padding: 3px;
  margin-top: 2em;
  margin-left: -30px;
  border: 1px solid #999;
}

.top-aligned-row {
  vertical-align: top
}

.bottom-aligned-row {
  vertical-align: bottom
}

#diagram img {
  border: 0;
}

/* --- Context section classes ----------------------- */

.context-row { }

.context-item-name {
  font-family: monospace;
  font-weight: bold;
  color: black;
}

.context-item-value {
  font-size: small;
  color: #448;
}

.context-item-desc {
  color: #333;
  padding-left: 2em;
}

/* --- Method classes -------------------------- */

.method-detail {
  background: #efefef;
  padding: 0;
  margin-top: 0.5em;
  margin-bottom: 1em;
  border: 1px dotted #ccc;
}

.method-heading {
  color: black;
  background: #ccc;
  border-bottom: 1px solid #666;
  padding: 0.2em 0.5em 0 0.5em;
}

.method-signature {
  color: black;
  background: inherit;
}

.method-name {
  font-weight: bold;
}

.method-args {
  font-style: italic;
}

.method-description {
  padding: 0 0.5em 0 0.5em;
}

/* --- Source code sections -------------------- */

:link.source-toggle, :visited.source-toggle {
  font-size: 90%;
}

div.method-source-code {
  background: #262626;
  color: #ffdead;
  margin: 1em;
  padding: 0.5em;
  border: 1px dashed #999;
  overflow: auto;
}

div.method-source-code pre {
  color: #ffdead;
}

/* --- Ruby keyword styles --------------------- */

.standalone-code {
  background: #221111;
  color: #ffdead;
  overflow: auto;
}

.ruby-constant {
  color: #7fffd4;
  background: transparent;
}

.ruby-keyword {
  color: #00ffff;
  background: transparent;
}

.ruby-ivar {
  color: #eedd82;
  background: transparent;
}

.ruby-operator {
  color: #00ffee;
  background: transparent;
}

.ruby-identifier {
  color: #ffdead;
  background: transparent;
}

.ruby-node {
  color: #ffa07a;
  background: transparent;
}

.ruby-comment {
  color: #b22222;
  font-weight: bold;
  background: transparent;
}

.ruby-regexp {
  color: #ffa07a;
  background: transparent;
}

.ruby-value {
  color: #7fffd4;
  background: transparent;
}
EOF


#####################################################################
### H E A D E R   T E M P L A T E
#####################################################################

  HEADER = XHTML_STRICT_PREAMBLE + HTML_ELEMENT + <<-EOF
<head>
  <title><%= values["title"] %></title>
  <meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>" />
  <meta http-equiv="Content-Script-Type" content="text/javascript" />
  <link rel="stylesheet" href="<%= values["style_url"] %>" type="text/css" media="screen" />
  <script type="text/javascript">
  // <![CDATA[

  function popupCode( url ) {
    window.open(url, "Code", "resizable=yes,scrollbars=yes,toolbar=no,status=no,height=150,width=400")
  }

  function toggleCode( id ) {
    if ( document.getElementById )
      elem = document.getElementById( id );
    else if ( document.all )
      elem = eval( "document.all." + id );
    else
      return false;

    elemStyle = elem.style;

    if ( elemStyle.display != "block" ) {
      elemStyle.display = "block"
    } else {
      elemStyle.display = "none"
    }

    return true;
  }

  // Make codeblocks hidden by default
  document.writeln( "<style type=\\"text/css\\">div.method-source-code { display: none }<\\/style>" )

  // ]]>
  </script>

</head>
<body>
EOF

#####################################################################
### F O O T E R   T E M P L A T E
#####################################################################

  FOOTER = <<-EOF
<div id="validator-badges">
  <p><small><a href="http://validator.w3.org/check/referer">[Validate]</a></small></p>
</div>

</body>
</html>
  EOF


#####################################################################
### F I L E   P A G E   H E A D E R   T E M P L A T E
#####################################################################

  FILE_PAGE = <<-EOF
  <div id="fileHeader">
    <h1><%= values["short_name"] %></h1>
    <table class="header-table">
    <tr class="top-aligned-row">
      <td><strong>Path:</strong></td>
      <td><%= values["full_path"] %>
<% if values["cvsurl"] then %>
        &nbsp;(<a href="<%= values["cvsurl"] %>"><acronym title="Concurrent Versioning System">CVS</acronym></a>)
<% end %>
      </td>
    </tr>
    <tr class="top-aligned-row">
      <td><strong>Last Update:</strong></td>
      <td><%= values["dtm_modified"] %></td>
    </tr>
    </table>
  </div>
  EOF

#####################################################################
### C L A S S   P A G E   H E A D E R   T E M P L A T E
#####################################################################

  CLASS_PAGE = <<-EOF
    <div id="classHeader">
        <table class="header-table">
        <tr class="top-aligned-row">
          <td><strong><%= values["classmod"] %></strong></td>
          <td class="class-name-in-header"><%= values["full_name"] %></td>
        </tr>
        <tr class="top-aligned-row">
            <td><strong>In:</strong></td>
            <td>
<% values["infiles"].each do |infiles| %>
<% if infiles["full_path_url"] then %>
                <a href="<%= infiles["full_path_url"] %>">
<% end %>
                <%= infiles["full_path"] %>
<% if infiles["full_path_url"] then %>
                </a>
<% end %>
<% if infiles["cvsurl"] then %>
        &nbsp;(<a href="<%= infiles["cvsurl"] %>"><acronym title="Concurrent Versioning System">CVS</acronym></a>)
<% end %>
        <br />
<% end %><%# values["infiles"] %>
            </td>
        </tr>

<% if values["parent"] then %>
        <tr class="top-aligned-row">
            <td><strong>Parent:</strong></td>
            <td>
<% if values["par_url"] then %>
                <a href="<%= values["par_url"] %>">
<% end %>
                <%= values["parent"] %>
<% if values["par_url"] then %>
               </a>
<% end %>
            </td>
        </tr>
<% end %>
        </table>
    </div>
  EOF

#####################################################################
### M E T H O D   L I S T   T E M P L A T E
#####################################################################

  METHOD_LIST = <<-EOF
  <div id="contextContent">
<% if values["diagram"] then %>
    <div id="diagram">
      <%= values["diagram"] %>
    </div>
<% end

   if values["description"] then %>
    <div id="description">
      <%= values["description"] %>
    </div>
<% end

   if values["requires"] then %>
    <div id="requires-list">
      <h3 class="section-bar">Required files</h3>

      <div class="name-list">
<% values["requires"].each do |requires| %>
        <%= href requires["aref"], requires["name"] %>&nbsp;&nbsp;
<% end %><%# values["requires"] %>
      </div>
    </div>
<% end

   if values["toc"] then %>
    <div id="contents-list">
      <h3 class="section-bar">Contents</h3>
      <ul>
<% values["toc"].each do |toc| %>
      <li><a href="#<%= toc["href"] %>"><%= toc["secname"] %></a></li>
<% end %><%# values["toc"] %>
     </ul>
<% end %>
   </div>

<% if values["methods"] then %>
    <div id="method-list">
      <h3 class="section-bar">Methods</h3>

      <div class="name-list">
<%   values["methods"].each do |methods| %>
        <%= href methods["aref"], methods["name"] %>&nbsp;&nbsp;
<%   end %><%# values["methods"] %>
      </div>
    </div>
<% end %>
  </div>

    <!-- if includes -->
<% if values["includes"] then %>
    <div id="includes">
      <h3 class="section-bar">Included Modules</h3>

      <div id="includes-list">
<% values["includes"].each do |includes| %>
        <span class="include-name"><%= href includes["aref"], includes["name"] %></span>
<% end %><%# values["includes"] %>
      </div>
    </div>
<% end

   values["sections"].each do |sections| %>
    <div id="section">
<%   if sections["sectitle"] then %>
      <h2 class="section-title"><a name="<%= sections["secsequence"] %>"><%= sections["sectitle"] %></a></h2>
<%     if sections["seccomment"] then %>
      <div class="section-comment">
        <%= sections["seccomment"] %>
      </div>
<%     end
     end

     if sections["classlist"] then %>
    <div id="class-list">
      <h3 class="section-bar">Classes and Modules</h3>

      <%= sections["classlist"] %>
    </div>
<%   end

     if sections["constants"] then %>
    <div id="constants-list">
      <h3 class="section-bar">Constants</h3>

      <div class="name-list">
        <table summary="Constants">
<%     sections["constants"].each do |constants| %>
        <tr class="top-aligned-row context-row">
          <td class="context-item-name"><%= constants["name"] %></td>
          <td>=</td>
          <td class="context-item-value"><%= constants["value"] %></td>
<%       if constants["desc"] then %>
          <td>&nbsp;</td>
          <td class="context-item-desc"><%= constants["desc"] %></td>
<%       end %>
        </tr>
<%     end %><%# sections["constants"] %>
        </table>
      </div>
    </div>
<%   end

     if sections["aliases"] then %>
    <div id="aliases-list">
      <h3 class="section-bar">External Aliases</h3>

      <div class="name-list">
      <table summary="aliases">
<%     sections["aliases"].each do |aliases| %>
        <tr class="top-aligned-row context-row">
          <td class="context-item-name"><%= aliases["old_name"] %></td>
          <td>-&gt;</td>
          <td class="context-item-value"><%= aliases["new_name"] %></td>
        </tr>
<%       if aliases["desc"] then %>
      <tr class="top-aligned-row context-row">
        <td>&nbsp;</td>
        <td colspan="2" class="context-item-desc"><%= aliases["desc"] %></td>
      </tr>
<%       end
       end %><%# sections["aliases"] %>
        </table>
      </div>
    </div>
<%   end %>

<%   if sections["attributes"] then %>
    <div id="attribute-list">
      <h3 class="section-bar">Attributes</h3>

      <div class="name-list">
        <table>
<%     sections["attributes"].each do |attribute| %>
        <tr class="top-aligned-row context-row">
          <td class="context-item-name"><%= attribute["name"] %></td>
<%       if attribute["rw"] then %>
          <td class="context-item-value">&nbsp;[<%= attribute["rw"] %>]&nbsp;</td>
<%       end
         unless attribute["rw"] then %>
          <td class="context-item-value">&nbsp;&nbsp;</td>
<%       end %>
          <td class="context-item-desc"><%= attribute["a_desc"] %></td>
        </tr>
<%     end %><%# sections["attributes"] %>
        </table>
      </div>
    </div>
<%   end %>

    <!-- if method_list -->
<%   if sections["method_list"] then %>
    <div id="methods">
<%     sections["method_list"].each do |method_list|
         if method_list["methods"] then %>
      <h3 class="section-bar"><%= method_list["type"] %> <%= method_list["category"] %> methods</h3>

<%         method_list["methods"].each do |methods| %>
      <div id="method-<%= methods["aref"] %>" class="method-detail">
        <a name="<%= methods["aref"] %>"></a>

        <div class="method-heading">
<%           if methods["codeurl"] then %>
          <a href="<%= methods["codeurl"] %>" target="Code" class="method-signature"
            onclick="popupCode('<%= methods["codeurl"] %>');return false;">
<%           end
             if methods["sourcecode"] then %>
          <a href="#<%= methods["aref"] %>" class="method-signature">
<%           end
             if methods["callseq"] then %>
          <span class="method-name"><%= methods["callseq"] %></span>
<%           end
             unless methods["callseq"] then %>
          <span class="method-name"><%= methods["name"] %></span><span class="method-args"><%= methods["params"] %></span>
<%           end
             if methods["codeurl"] then %>
          </a>
<%           end
             if methods["sourcecode"] then %>
          </a>
<%           end %>
        </div>

        <div class="method-description">
<%           if methods["m_desc"] then %>
          <%= methods["m_desc"] %>
<%           end
               if methods["sourcecode"] then %>
          <p><a class="source-toggle" href="#"
            onclick="toggleCode('<%= methods["aref"] %>-source');return false;">[Source]</a></p>
          <div class="method-source-code" id="<%= methods["aref"] %>-source">
<pre>
<%= methods["sourcecode"] %>
</pre>
          </div>
<%           end %>
        </div>
      </div>

<%         end %><%# method_list["methods"] %><%
         end
       end %><%# sections["method_list"] %>

    </div>
<%   end %>
<% end %><%# values["sections"] %>
  EOF

#####################################################################
### B O D Y   T E M P L A T E
#####################################################################

  BODY = HEADER + %{

<%= template_include %>  <!-- banner header -->

  <div id="bodyContent">

} +  METHOD_LIST + %{

  </div>

} + FOOTER

#####################################################################
### S O U R C E   C O D E   T E M P L A T E
#####################################################################

  SRC_PAGE = XHTML_STRICT_PREAMBLE + HTML_ELEMENT + <<-EOF
<head>
  <title><%= values["title"] %></title>
  <meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>" />
  <link rel="stylesheet" href="<%= values["style_url"] %>" type="text/css" media="screen" />
</head>
<body class="standalone-code">
  <pre><%= values["code"] %></pre>
</body>
</html>
  EOF


#####################################################################
### I N D E X   F I L E   T E M P L A T E S
#####################################################################

  FR_INDEX_BODY = %{<%= template_include %>}

  FILE_INDEX = XHTML_STRICT_PREAMBLE + HTML_ELEMENT + <<-EOF
<!--

    <%= values["title"] %>

  -->
<head>
  <title><%= values["title"] %></title>
  <meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>" />
  <link rel="stylesheet" href="<%= values["style_url"] %>" type="text/css" />
  <base target="docwin" />
</head>
<body>
<div class="index">
  <h1 class="section-bar"><%= values["list_title"] %></h1>
  <div id="index-entries">
<% values["entries"].each do |entries| %>
    <a href="<%= entries["href"] %>"><%= entries["name"] %></a><br />
<% end %><%#  values["entries"] %>
  </div>
</div>
</body>
</html>
  EOF

  CLASS_INDEX = FILE_INDEX
  METHOD_INDEX = FILE_INDEX

  INDEX = XHTML_FRAME_PREAMBLE + HTML_ELEMENT + <<-EOF
<!--

    <%= values["title"] %>

  -->
<head>
  <title><%= values["title"] %></title>
  <meta http-equiv="Content-Type" content="text/html; charset=<%= values["charset"] %>" />
</head>
<frameset rows="20%, 80%">
    <frameset cols="25%,35%,45%">
        <frame src="fr_file_index.html"   title="Files" name="Files" />
        <frame src="fr_class_index.html"  name="Classes" />
        <frame src="fr_method_index.html" name="Methods" />
    </frameset>
    <frame src="<%= values["initial_page"] %>" name="docwin" />
</frameset>
</html>
  EOF

end

