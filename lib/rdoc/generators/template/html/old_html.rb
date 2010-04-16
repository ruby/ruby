module RDoc

# This is how you define the HTML that RDoc generates. Simply create
# a file in rdoc/generators/html_templates that creates the
# module RDoc::Page and populate it as described below. Then invoke
# rdoc using the --template <name of your file> option, and
# your template will be used.
#
# The constants defining pages use a simple templating system:
#
# * The templating system is passed a hash. Keys in the hash correspond
#   to tags on this page. The tag %abc% is looked up in the hash,
#   and is replaced by the corresponding hash value.
#
# * Some tags are optional. You can detect this using IF/ENDIF
#
#      IF: title
#      The value of title is %title%
#      ENDIF: title
#
# * Some entries in the hash have values that are arrays, where each
#   entry in the array is itself a hash. These are used to generate
#   lists using the START: construct. For example, given a hash
#   containing
#
#      { 'people' => [ { 'name' => 'Fred', 'age' => '12' },
#                      { 'name' => 'Mary', 'age' => '21' } ]
#
#   You could generate a simple table using
#
#      <table>
#      START:people
#        <tr><td>%name%<td>%age%</tr>
#      END:people
#      </table>
#
#   These lists can be nested to an arbitrary depth
#
# * the construct HREF:url:name: generates <a href="%url%">%name%</a>
#   if +url+ is defined in the hash, or %name% otherwise.
#
#
# Your file must contain the following constants
#
# [*FONTS*]  a list of fonts to be used
# [*STYLE*]  a CSS section (without the <style> or comments). This is
#            used to generate a style.css file
#
# [*BODY*]
#   The main body of all non-index RDoc pages. BODY will contain
#   two !INCLUDE!s. The first is used to include a document-type
#   specific header (FILE_PAGE or CLASS_PAGE). The second include
#   is for the method list (METHOD_LIST). THe body is passed:
#
#   %title%::
#       the page's title
#
#   %style_url%::
#       the url of a style sheet for this page
#
#   %diagram%::
#       the optional URL of a diagram for this page
#
#   %description%::
#       a (potentially multi-paragraph) string containing the
#       description for th file/class/module.
#
#   %requires%::
#       an optional list of %aref%/%name% pairs, one for each module
#       required by this file.
#
#   %methods%::
#       an optional list of %aref%/%name%, one for each method
#       documented on this page. This is intended to be an index.
#
#   %attributes%::
#       An optional list. For each attribute it contains:
#       %name%::   the attribute name
#       %rw%::     r/o, w/o, or r/w
#       %a_desc%:: description of the attribute
#
#   %classlist%::
#       An optional string containing an already-formatted list of
#       classes and modules documented in this file
#
#   For FILE_PAGE entries, the body will be passed
#
#   %short_name%::
#       The name of the file
#
#   %full_path%::
#       The full path to the file
#
#   %dtm_modified%::
#       The date/time the file was last changed
#
#   For class and module pages, the body will be passed
#
#   %classmod%::
#       The name of the class or module
#
#   %files%::
#       A list. For each file this class is defined in, it contains:
#       %full_path_url%:: an (optional) URL of the RDoc page
#                         for this file
#       %full_path%::     the name of the file
#
#   %par_url%::
#       The (optional) URL of the RDoc page documenting this class's
#       parent class
#
#   %parent%::
#       The name of this class's parent.
#
#   For both files and classes, the body is passed the following information
#   on includes and methods:
#
#   %includes%::
#       Optional list of included modules. For each, it receives
#       %aref%:: optional URL to RDoc page for the module
#       %name%:: the name of the module
#
#   %method_list%::
#       Optional list of methods of a particular class and category.
#
#   Each method list entry contains:
#
#   %type%::        public/private/protected
#   %category%::    instance/class
#   %methods%::     a list of method descriptions
#
#   Each method description contains:
#
#   %aref%::        a target aref, used when referencing this method
#                   description. You should code this as <a name="%aref%">
#   %codeurl%::     the optional URL to the page containing this method's
#                   source code.
#   %name%::        the method's name
#   %params%::      the method's parameters
#   %callseq%::     a full calling sequence
#   %m_desc%::      the (potentially multi-paragraph) description of
#                   this method.
#
# [*CLASS_PAGE*]
#         Header for pages documenting classes and modules. See
#         BODY above for the available parameters.
#
# [*FILE_PAGE*]
#         Header for pages documenting files. See
#         BODY above for the available parameters.
#
# [*METHOD_LIST*]
#         Controls the display of the listing of methods. See BODY for
#         parameters.
#
# [*INDEX*]
#         The top-level index page. For a browser-like environment
#         define a frame set that includes the file, class, and
#         method indices. Passed
#         %title%:: title of page
#         %initial_page% :: url of initial page to display
#
# [*CLASS_INDEX*]
#         Individual files for the three indexes. Passed:
#         %index_url%:: URL of main index page
#         %entries%::   List of
#                       %name%:: name of an index entry
#                       %href%:: url of corresponding page
# [*METHOD_INDEX*]
#         Same as CLASS_INDEX for methods
#
# [*FILE_INDEX*]
#         Same as CLASS_INDEX for methods
#
# [*FR_INDEX_BODY*]
#         A wrapper around CLASS_INDEX, METHOD_INDEX, and FILE_INDEX.
#         If those index strings contain the complete HTML for the
#         output, then FR_INDEX_BODY can simply be !INCLUDE!
#
# [*SRC_PAGE*]
#         Page used to display source code. Passed %title% and %code%,
#         the latter being a multi-line string of code.

module Page

FONTS = "Verdana, Arial, Helvetica, sans-serif"

STYLE = %{
body,td,p { font-family: %fonts%;
       color: #000040;
}

.attr-rw { font-size: x-small; color: #444488 }

.title-row { background: #0000aa;
             color:      #eeeeff;
}

.big-title-font { color: white;
                  font-family: %fonts%;
                  font-size: large;
                  height: 50px}

.small-title-font { color: aqua;
                    font-family: %fonts%;
                    font-size: xx-small; }

.aqua { color: aqua }

.method-name, attr-name {
      font-family: monospace; font-weight: bold;
}

.tablesubtitle, .tablesubsubtitle {
   width: 100%;
   margin-top: 1ex;
   margin-bottom: .5ex;
   padding: 5px 0px 5px 20px;
   font-size: large;
   color: aqua;
   background: #3333cc;
}

.name-list {
  font-family: monospace;
  margin-left: 40px;
  margin-bottom: 2ex;
  line-height: 140%;
}

.description {
  margin-left: 40px;
  margin-top: -2ex;
  margin-bottom: 2ex;
}

.description p {
  line-height: 140%;
}

.aka {
  margin-left: 40px;
  margin-bottom: 2ex;
  line-height: 100%;
  font-size:   small;
  color:       #808080;
}

.methodtitle {
  font-size: medium;
  text-decoration: none;
  color: #0000AA;
  background: white;
}

.paramsig {
   font-size: small;
}

.srcbut { float: right }

pre { font-size: 1.2em; }
tt  { font-size: 1.2em; }

pre.source {
  border-style: groove;
  background-color: #ddddff;
  margin-left:  40px;
  padding: 1em 0em 1em 2em;
}

.classlist {
  margin-left: 40px;
  margin-bottom: 2ex;
  line-height: 140%;
}

li {
  display:    list-item;
  margin-top: .6em;
}

.ruby-comment    { color: green; font-style: italic }
.ruby-constant   { color: #4433aa; font-weight: bold; }
.ruby-identifier { color: #222222;  }
.ruby-ivar       { color: #2233dd; }
.ruby-keyword    { color: #3333FF; font-weight: bold }
.ruby-node       { color: #777777; }
.ruby-operator   { color: #111111;  }
.ruby-regexp     { color: #662222; }
.ruby-value      { color: #662222; font-style: italic }

}


############################################################################


HEADER = %{
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
  <title>%title%</title>
  <meta http-equiv="Content-Type" content="text/html; charset=%charset%" />
  <link rel=StyleSheet href="%style_url%" type="text/css" media="screen" />
  <script type="text/javascript" language="JavaScript">
  <!--
  function popCode(url) {
    window.open(url, "Code",
          "resizable=yes,scrollbars=yes,toolbar=no,status=no,height=150,width=400")
  }
  //-->
  </script>
</head>
}


###################################################################

METHOD_LIST = %{
IF:includes
<table summary="Included modules" cellpadding="5" width="100%">
<tr><td class="tablesubtitle">Included modules</td></tr>
</table>
<div class="name-list">
START:includes
    <span class="method-name">HREF:aref:name:</span>
END:includes
</div>
ENDIF:includes

IF:method_list
START:method_list
IF:methods
<table summary="Method list" cellpadding="5" width="100%">
<tr><td class="tablesubtitle">%type% %category% methods</td></tr>
</table>
START:methods
<table summary="method"  width="100%" cellspacing="0" cellpadding="5" border="0">
<tr><td class="methodtitle">
<a name="%aref%"></a>
IF:codeurl
<a href="%codeurl%" target="Code" class="methodtitle"
 onClick="popCode('%codeurl%');return false;">
ENDIF:codeurl
IF:callseq
<b>%callseq%</b>
ENDIF:callseq
IFNOT:callseq
<b>%name%</b>%params%
ENDIF:callseq
IF:codeurl
</a>
ENDIF:codeurl
</td></tr>
</table>
IF:m_desc
<div class="description">
%m_desc%
</div>
ENDIF:m_desc
IF:aka
<div class="aka">
This method is also aliased as
START:aka
<a href="%aref%">%name%</a>
END:aka
</div>
ENDIF:aka
IF:sourcecode
<pre class="source">
%sourcecode%
</pre>
ENDIF:sourcecode
END:methods
ENDIF:methods
END:method_list
ENDIF:method_list
}

###################################################################

CONTEXT_CONTENT = %{
IF:diagram
<table summary="Diagram of classes and modules" width="100%">
<tr><td align="center">
%diagram%
</td></tr></table>
ENDIF:diagram


IF:description
<div class="description">%description%</div>
ENDIF:description

IF:requires
<table summary="Requires" cellpadding="5" width="100%">
<tr><td class="tablesubtitle">Required files</td></tr>
</table>
<div class="name-list">
START:requires
HREF:aref:name:&nbsp; &nbsp;
END:requires
</div>
ENDIF:requires

IF:methods
<table summary="Methods" cellpadding="5" width="100%">
<tr><td class="tablesubtitle">Methods</td></tr>
</table>
<div class="name-list">
START:methods
HREF:aref:name:&nbsp; &nbsp;
END:methods
</div>
ENDIF:methods

IF:constants
<table summary="Constants" cellpadding="5" width="100%">
<tr><td class="tablesubtitle">Constants</td></tr>
</table>
<table cellpadding="5">
START:constants
<tr valign="top"><td>%name%</td><td>=</td><td>%value%</td></tr>
IF:desc
<tr><td></td><td></td><td>%desc%</td></tr>
ENDIF:desc
END:constants
</table>
ENDIF:constants

IF:aliases
<table summary="Aliases" cellpadding="5" width="100%">
<tr><td class="tablesubtitle">External Aliases</td></tr>
</table>
<div class="name-list">
START:aliases
%old_name% -> %new_name%<br />
END:aliases
</div>
ENDIF:aliases

IF:attributes
<table summary="Attributes" cellpadding="5" width="100%">
<tr><td class="tablesubtitle">Attributes</td></tr>
</table>
<table summary="Attribute details" cellspacing="5">
START:attributes
     <tr valign="top">
       <td class="attr-name">%name%</td>
IF:rw
       <td align="center" class="attr-rw">&nbsp;[%rw%]&nbsp;</td>
ENDIF:rw
IFNOT:rw
       <td></td>
ENDIF:rw
       <td>%a_desc%</td>
     </tr>
END:attributes
</table>
ENDIF:attributes

IF:classlist
<table summary="List of classes" cellpadding="5" width="100%">
<tr><td class="tablesubtitle">Classes and Modules</td></tr>
</table>
<div class="classlist">
%classlist%
</div>
ENDIF:classlist
}

###############################################################################

BODY = HEADER + %{
<body bgcolor="white">
!INCLUDE!  <!-- banner header -->
} +
CONTEXT_CONTENT + METHOD_LIST +
%{
</body>
</html>
}


###############################################################################

FILE_PAGE = <<_FILE_PAGE_
<table summary="Information on file" width="100%">
 <tr class="title-row">
 <td><table summary="layout" width="100%"><tr>
   <td class="big-title-font" colspan="2">%short_name%</td>
   <td align="right"><table summary="layout" cellspacing="0" cellpadding="2">
         <tr>
           <td  class="small-title-font">Path:</td>
           <td class="small-title-font">%full_path%
IF:cvsurl
				&nbsp;(<a href="%cvsurl%"><acronym title="Concurrent Versioning System">CVS</acronym></a>)
ENDIF:cvsurl
           </td>
         </tr>
         <tr>
           <td class="small-title-font">Modified:</td>
           <td class="small-title-font">%dtm_modified%</td>
         </tr>
        </table>
    </td></tr></table></td>
  </tr>
</table>
_FILE_PAGE_

###################################################################

CLASS_PAGE = %{
<table summary="Information on class" width="100%" border="0" cellspacing="0">
 <tr class="title-row">
 <td class="big-title-font">
   <sup><font color="aqua">%classmod%</font></sup> %full_name%
 </td>
 <td align="right">
   <table summary="layout" cellspacing="0" cellpadding="2">
     <tr valign="top">
      <td class="small-title-font">In:</td>
      <td class="small-title-font">
START:infiles
IF:full_path_url
        <a href="%full_path_url%" class="aqua">
ENDIF:full_path_url
%full_path%
IF:full_path_url
         </a>
ENDIF:full_path_url
IF:cvsurl
         &nbsp;(<a href="%cvsurl%"><acronym title="Concurrent Versioning System">CVS</acronym></a>)
ENDIF:cvsurl
<br />
END:infiles
      </td>
     </tr>
IF:parent
     <tr>
      <td class="small-title-font">Parent:</td>
      <td class="small-title-font">
IF:par_url
        <a href="%par_url%" class="aqua">
ENDIF:par_url
%parent%
IF:par_url
         </a>
ENDIF:par_url
      </td>
     </tr>
ENDIF:parent
   </table>
  </td>
  </tr>
</table>
}

=begin
=end

########################## Source code ##########################

SRC_PAGE = %{
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=%charset%">
<title>%title%</title>
<link rel="stylesheet" href="%style_url%" type="text/css" media="screen" />
</head>
<body bgcolor="white">
<pre>%code%</pre>
</body>
</html>
}

########################## Index ################################

FR_INDEX_BODY = %{
!INCLUDE!
}

FILE_INDEX = %{
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=%charset%">
<title>%list_title%</title>
<style type="text/css">
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
  color:      white;
  padding: 1;
  margin: 0;
  font-size: 90%;
  font-weight: bold;
  line-height: 1.1;
  text-align: center;
  width: 100%;
}

A.xx { color: white; font-weight: bold; }
-->
</style>
<base target="docwin">
</head>
<body>
<div class="banner"><a href="%index_url%" class="xx">%list_title%</a></div>
START:entries
<a href="%href%">%name%</a><br />
END:entries
</body></html>
}

CLASS_INDEX = FILE_INDEX
METHOD_INDEX = FILE_INDEX

INDEX = %{
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Frameset//EN">
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=%charset%">
<title>%title%</title></head>

<frameset rows="20%, 80%">
    <frameset cols="25%,35%,45%">
        <frame src="fr_file_index.html"   title="Files" name="Files">
        <frame src="fr_class_index.html"  name="Classes">
        <frame src="fr_method_index.html" name="Methods">
    </frameset>
    <frame  src="%initial_page%" name="docwin">
    <noframes>
          <body bgcolor="white">
            Sorry, RDoc currently only generates HTML using frames.
          </body>
    </noframes>
</frameset>

</html>
}

######################################################################
#
# The following is used for the -1 option
#

CONTENTS_XML = %{
IF:description
%description%
ENDIF:description

IF:requires
<h4>Requires:</h4>
<ul>
START:requires
IF:aref
<li><a href="%aref%">%name%</a></li>
ENDIF:aref
IFNOT:aref
<li>%name%</li>
ENDIF:aref
END:requires
</ul>
ENDIF:requires

IF:attributes
<h4>Attributes</h4>
<table>
START:attributes
<tr><td>%name%</td><td>%rw%</td><td>%a_desc%</td></tr>
END:attributes
</table>
ENDIF:attributes

IF:includes
<h4>Includes</h4>
<ul>
START:includes
IF:aref
<li><a href="%aref%">%name%</a></li>
ENDIF:aref
IFNOT:aref
<li>%name%</li>
ENDIF:aref
END:includes
</ul>
ENDIF:includes

IF:method_list
<h3>Methods</h3>
START:method_list
IF:methods
START:methods
<h4>%type% %category% method: <a name="%aref%">%name%%params%</a></h4>

IF:m_desc
%m_desc%
ENDIF:m_desc

IF:sourcecode
<blockquote><pre>
%sourcecode%
</pre></blockquote>
ENDIF:sourcecode
END:methods
ENDIF:methods
END:method_list
ENDIF:method_list
}


end
end

require 'rdoc/generators/template/html/one_page_html'
