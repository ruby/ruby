#
# = CSS2 RDoc HTML template
#
# This is a template for RDoc that uses XHTML 1.0 Transitional and dictates a
# bit more of the appearance of the output to cascading stylesheets than the
# default. It was designed for clean inline code display, and uses DHTMl to
# toggle the visbility of each method's source with each click on the '[source]'
# link.
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
#

module RDoc
	module Page

		FONTS = "Verdana,Arial,Helvetica,sans-serif"

STYLE = %{
body {
    margin: 0;
    padding: 0;
    background: white;
}

h1,h2,h3,h4 { margin: 0; color: #efefef; background: transparent; }
h1 { font-size: 120%; }
h2,h3,h4 { margin-top: 1em; }

a { background: #eef; color: #039; text-decoration: none; }
a:hover { background: #039; color: #eef; }

/* Override the base stylesheet's Anchor inside a table cell */
td > a {
	background: transparent;
	color: #039;
	text-decoration: none;
}

/* === Structural elements =================================== */

div#index {
    margin: 0;
    padding: 0;
    font-size: 0.9em;
}

div#index a {
    margin-left: 0.7em;
}

div#classHeader {
    width: auto;
    background: #039;
    color: white;
    padding: 0.5em 1.5em 0.5em 1.5em;
    margin: 0;
    border-bottom: 3px solid #006;
}

div#classHeader a {
    background: inherit;
    color: white;
}

div#classHeader td {
    background: inherit;
    color: white;
}

div#fileHeader {
    width: auto;
    background: #039;
    color: white;
    padding: 0.5em 1.5em 0.5em 1.5em;
    margin: 0;
    border-bottom: 3px solid #006;
}

div#fileHeader a {
    background: inherit;
    color: white;
}

div#fileHeader td {
    background: inherit;
    color: white;
}

div#bodyContent {
    padding: 0 1.5em 0 1.5em;
}

div#description {
    padding: 0.5em 1.5em;
    background: #efefef;
    border: 1px dotted #999;
}

div#description h1,h2,h3,h4,h5,h6 {
    color: black;
    background: transparent;
}

div#validator-badges {
    text-align: center;
}
div#validator-badges img { border: 0; }

div#copyright {
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
    color: #DEDEDE;
}

.section-bar {
    background: #eee;
    color: #333;
    padding: 3px;
    border: 1px solid #999;
}

.top-aligned-row { vertical-align: vertical-align: top }

/* --- Context section classes ----------------------- */

.context-row { }
.context-item-name { font-family: monospace; font-weight: bold; color: black; }
.context-item-value { font-size: x-small; color: #448; }
.context-item-desc { background: #efefef; }

/* --- Method classes -------------------------- */
.method-detail {
    background: #EFEFEF;
    padding: 0;
    margin-top: 0.5em;
    margin-bottom: 0.5em;
    border: 1px dotted #DDD;
}
.method-heading {
	color: black;
	background: #AAA;
	border-bottom: 1px solid #666;
	padding: 0.2em 0.5em 0 0.5em;
}
.method-signature { color: black; background: inherit; }
.method-name { font-weight: bold; }
.method-args { font-style: italic; }
.method-description { padding: 0 0.5em 0 0.5em; }

/* --- Source code sections -------------------- */

a.source-toggle { font-size: 90%; }
div.method-source-code {
    background: #262626;
    color: #ffdead;
	margin: 1em;
    padding: 0.5em;
    border: 1px dashed #999;
    overflow: hidden;
}

div.method-source-code pre { color: #ffdead; overflow: hidden; }

/* --- Ruby keyword styles --------------------- */
/* (requires a hacked html_generator.rb to add more class-types) */
.ruby-constant	{ color: #7fffd4; background: transparent; }
.ruby-keyword	{ color: #00ffff; background: transparent; }
.ruby-ivar		{ color: #eedd82; background: transparent; }
.ruby-operator	{ color: #00ffee; background: transparent; }
.ruby-identifier { color: #ffdead; background: transparent; }
.ruby-node		{ color: #ffa07a; background: transparent; }
.ruby-comment	{ color: #b22222; font-weight: bold; background: transparent; }
.ruby-regexp	{ color: #ffa07a; background: transparent; }
.ruby-value		{ color: #7fffd4; background: transparent; }
}


#####################################################################
###	H E A D E R   T E M P L A T E  
#####################################################################

XHTML_PREAMBLE = %{<?xml version="1.0" encoding="%charset%"?>
<!DOCTYPE html 
     PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
     "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
}

HEADER = XHTML_PREAMBLE + %{
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<title>%title%</title>
	<meta http-equiv="Content-Type" content="text/html; charset=%charset%" />
	<meta http-equiv="Content-Script-Type" content="text/javascript" />
	<link rel="stylesheet" href="%style_url%" type="text/css" media="screen" />
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
	document.writeln( "<style type=\\"text/css\\">div.method-source-code { display: none }</style>" )
	
	// ]]>
	</script>

</head>
<body>
}


#####################################################################
###	C O N T E X T   C O N T E N T   T E M P L A T E
#####################################################################

CONTEXT_CONTENT = %{
	<div id="contextContent">
IF:diagram
		<div id="diagram">
			%diagram%
		</div>
ENDIF:diagram

IF:description
		<div id="description">
			%description%
		</div>
ENDIF:description

IF:requires
		<div id="requires-list">
			<h2 class="section-bar">Required files</h2>

			<div class="name-list">
START:requires
			HREF:aref:name:&nbsp;&nbsp;
END:requires
			</div>
		</div>
ENDIF:requires

IF:methods
		<div id="method-list">
			<h2 class="section-bar">Methods</h2>

			<div class="name-list">
START:methods
			HREF:aref:name:&nbsp;&nbsp;
END:methods
			</div>
		</div>
ENDIF:methods

IF:constants
		<div id="constants-list">
			<h2 class="section-bar">Constants</h2>

			<div class="name-list">
				<table summary="Constants">
START:constants
				<tr class="top-aligned-row context-row">
					<td class="context-item-name">%name%</td>
					<td>=</td>
					<td class="context-item-value">%value%</td>
				</tr>
IF:desc
				<tr class="top-aligned-row context-row">
					<td>&nbsp;</td>
					<td colspan="2" class="context-item-desc">%desc%</td>
				</tr>
ENDIF:desc
END:constants
				</table>
			</div>
		</div>
ENDIF:constants

IF:aliases
		<div id="aliases-list">
			<h2 class="section-bar">External Aliases</h2>

			<div class="name-list">
                        <table summary="aliases">
START:aliases
				<tr class="top-aligned-row context-row">
					<td class="context-item-name">%old_name%</td>
					<td>-></td>
					<td class="context-item-value">%new_name%</td>
				</tr>
IF:desc
			<tr class="top-aligned-row context-row">
				<td>&nbsp;</td>
				<td colspan="2" class="context-item-desc">%desc%</td>
			</tr>
ENDIF:desc
END:aliases
                        </table>
			</div>
		</div>
ENDIF:aliases


IF:attributes
		<div id="attribute-list">
			<h2 class="section-bar">Attributes</h2>

			<div class="name-list">
				<table>
START:attributes
				<tr class="top-aligned-row context-row">
					<td class="context-item-name">%name%</td>
					<td class="context-item-value">&nbsp;[%rw%]&nbsp;</td>
					<td class="context-item-desc">%a_desc%</td>
				</tr>
END:attributes
				</table>
			</div>
		</div>
ENDIF:attributes
			
IF:classlist
		<div id="class-list">
			<h2 class="section-bar">Classes and Modules</h2>

			%classlist%
		</div>
ENDIF:classlist

	</div>

}


#####################################################################
###	F O O T E R   T E M P L A T E
#####################################################################
FOOTER = %{
<div id="validator-badges">
  <p><small><a href="http://validator.w3.org/check/referer">[Validate]</a></small></p>
</div>

</body>
</html>
}


#####################################################################
###	F I L E   P A G E   H E A D E R   T E M P L A T E
#####################################################################

FILE_PAGE = %{
	<div id="fileHeader">
		<h1>%short_name%</h1>
		<table class="header-table">
		<tr class="top-aligned-row">
			<td><strong>Path:</strong></td>
			<td>%full_path%
IF:cvsurl
				&nbsp;(<a href="%cvsurl%">CVS</a>)
ENDIF:cvsurl
			</td>
		</tr>
		<tr class="top-aligned-row">
			<td><strong>Last Update:</strong></td>
			<td>%dtm_modified%</td>
		</tr>
		</table>
	</div>
}


#####################################################################
###	C L A S S   P A G E   H E A D E R   T E M P L A T E
#####################################################################

CLASS_PAGE = %{
    <div id="classHeader">
        <h1>%full_name% <sup class="type-note">(%classmod%)</sup></h1>
        <table class="header-table">
        <tr class="top-aligned-row">
            <td><strong>In:</strong></td>
            <td>
START:infiles
IF:full_path_url
                <a href="%full_path_url%">
ENDIF:full_path_url
                %full_path%
IF:full_path_url
                </a>
ENDIF:full_path_url
IF:cvsurl
				&nbsp;(<a href="%cvsurl%">CVS</a>)
ENDIF:cvsurl
				<br />
END:infiles
            </td>
        </tr>

IF:parent
        <tr class="top-aligned-row">
            <td><strong>Parent:</strong></td>
            <td>
IF:par_url
                <a href="%par_url%">
ENDIF:par_url
                %parent%
IF:par_url
               </a>
ENDIF:par_url
            </td>
        </tr>
ENDIF:parent
        </table>
    </div>
}


#####################################################################
###	M E T H O D   L I S T   T E M P L A T E
#####################################################################

METHOD_LIST = %{

		<!-- if includes -->
IF:includes
		<div id="includes">
			<h2 class="section-bar">Included Modules</h2>

			<div id="includes-list">
START:includes
		    <span class="include-name">HREF:aref:name:</span>
END:includes
			</div>
		</div>
ENDIF:includes


		<!-- if method_list -->
IF:method_list
		<div id="methods">
START:method_list
IF:methods
			<h2 class="section-bar">%type% %category% methods</h2>

START:methods
			<div id="method-%aref%" class="method-detail">
				<a name="%aref%"></a>

				<div class="method-heading">
IF:codeurl
					<a href="%codeurl%" target="Code" class="method-signature"
						onclick="popupCode('%codeurl%');return false;">
ENDIF:codeurl
IF:sourcecode
					<a href="#%aref%" class="method-signature">
ENDIF:sourcecode
IF:callseq
					<span class="method-name">%callseq%</span>
ENDIF:callseq
IFNOT:callseq
					<span class="method-name">%name%</span><span class="method-args">%params%</span>
ENDIF:callseq
IF:codeurl
					</a>
ENDIF:codeurl
IF:sourcecode
					</a>
ENDIF:sourcecode
				</div>
			
				<div class="method-description">
IF:m_desc
					%m_desc%
ENDIF:m_desc
IF:sourcecode
					<p><a class="source-toggle" href="#"
					  onclick="toggleCode('%aref%-source');return false;">[Source]</a></p>
					<div class="method-source-code" id="%aref%-source">
<pre>
%sourcecode%
</pre>
					</div>
ENDIF:sourcecode
				</div>
			</div>

END:methods
ENDIF:methods
END:method_list

		</div>
ENDIF:method_list
}


#####################################################################
###	B O D Y   T E M P L A T E
#####################################################################

BODY = HEADER + %{

!INCLUDE!  <!-- banner header -->

	<div id="bodyContent">

} + CONTEXT_CONTENT + METHOD_LIST + %{

	</div>

} + FOOTER



#####################################################################
###	S O U R C E   C O D E   T E M P L A T E
#####################################################################

SRC_PAGE = XHTML_PREAMBLE + %{
<!--

    %title%

  -->
<html>
<head>
	<title>%title%</title>
	<meta http-equiv="Content-Type" content="text/html; charset=%charset%" />
	<link rel="stylesheet" href="http://www.FaerieMUD.org/stylesheets/rdoc.css" type="text/css" />
</head>
<body>
	<pre>%code%</pre>
</body>
</html>
}


#####################################################################
###	I N D E X   F I L E   T E M P L A T E S
#####################################################################

FR_INDEX_BODY = %{
!INCLUDE!
}

FILE_INDEX = XHTML_PREAMBLE + %{
<!--

    %list_title%

  -->
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<title>%list_title%</title>
	<meta http-equiv="Content-Type" content="text/html; charset=%charset%" />
	<link rel="stylesheet" href="%style_url%" type="text/css" />
	<base target="docwin" />
</head>
<body>
<div id="index">
	<h1 class="section-bar">%list_title%</h1>
	<div id="index-entries">
START:entries
		<a href="%href%">%name%</a><br />
END:entries
	</div>
</div>
</body>
</html>
}

CLASS_INDEX = FILE_INDEX
METHOD_INDEX = FILE_INDEX

INDEX = %{<?xml version="1.0" encoding="%charset%"?>
<!DOCTYPE html 
     PUBLIC "-//W3C//DTD XHTML 1.0 Frameset//EN"
     "http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd">

<!--

    %title%

  -->
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<title>%title%</title>
	<meta http-equiv="Content-Type" content="text/html; charset=%charset%" />
</head>
<frameset rows="20%, 80%">
    <frameset cols="25%,35%,45%">
        <frame src="fr_file_index.html"   title="Files" name="Files" />
        <frame src="fr_class_index.html"  name="Classes" />
        <frame src="fr_method_index.html" name="Methods" />
    </frameset>
    <frame src="%initial_page%" name="docwin" />
</frameset>
</html>
}



	end # module Page
end # class RDoc

require 'rdoc/generators/template/html/one_page_html'
