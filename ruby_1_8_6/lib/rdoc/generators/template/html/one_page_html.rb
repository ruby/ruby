module RDoc
module Page
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
<h4>%type% %category% method: 
IF:callseq
<a name="%aref%">%callseq%</a>
ENDIF:callseq
IFNOT:callseq
<a name="%aref%">%name%%params%</a></h4>
ENDIF:callseq

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

########################################################################

ONE_PAGE = %{
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
  <title>%title%</title>
  <meta http-equiv="Content-Type" content="text/html; charset=%charset%" />
</head>
<body>
START:files
<h2>File: %short_name%</h2>
<table>
  <tr><td>Path:</td><td>%full_path%</td></tr>
  <tr><td>Modified:</td><td>%dtm_modified%</td></tr>
</table>
} + CONTENTS_XML + %{
END:files

IF:classes
<h2>Classes</h2>
START:classes
IF:parent
<h3>%classmod% %full_name% &lt; HREF:par_url:parent:</h3>
ENDIF:parent
IFNOT:parent
<h3>%classmod% %full_name%</h3>
ENDIF:parent

IF:infiles
(in files
START:infiles
HREF:full_path_url:full_path:
END:infiles
)
ENDIF:infiles
} + CONTENTS_XML + %{
END:classes
ENDIF:classes
</body>
</html>
}

end
end
