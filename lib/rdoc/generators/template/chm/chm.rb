module RDoc
module Page

require "rdoc/generators/template/html/html"

# This is a nasty little hack, but hhc doesn't support the <?xml
# tag, so...

BODY.sub!(/<\?xml.*\?>/, '')

HPP_FILE = %{
[OPTIONS]
Auto Index = Yes
Compatibility=1.1 or later
Compiled file=%opname%.chm
Contents file=contents.hhc
Full-text search=Yes
Index file=index.hhk
Language=0x409 English(United States)
Title=%title%

[FILES]
START:all_html_files
%html_file_name%
END:all_html_files
}

CONTENTS = %{
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN">
<HTML>
<HEAD>
<meta name="GENERATOR" content="Microsoft&reg; HTML Help Workshop 4.1">
<!-- Sitemap 1.0 -->
</HEAD><BODY>
<OBJECT type="text/site properties">
	<param name="Foreground" value="0x80">
	<param name="Window Styles" value="0x800025">
	<param name="ImageType" value="Folder">
</OBJECT>
<UL>
START:contents
	<LI> <OBJECT type="text/sitemap">
		<param name="Name" value="%c_name%">
		<param name="Local" value="%ref%">
		</OBJECT>
IF:methods
<ul>
START:methods
	<LI> <OBJECT type="text/sitemap">
		<param name="Name" value="%name%">
		<param name="Local" value="%aref%">
		</OBJECT>
END:methods
</ul>
ENDIF:methods
        </LI>
END:contents
</UL>
</BODY></HTML>
}


CHM_INDEX  = %{
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN">
<HTML>
<HEAD>
<meta name="GENERATOR" content="Microsoft&reg; HTML Help Workshop 4.1">
<!-- Sitemap 1.0 -->
</HEAD><BODY>
<OBJECT type="text/site properties">
	<param name="Foreground" value="0x80">
	<param name="Window Styles" value="0x800025">
	<param name="ImageType" value="Folder">
</OBJECT>
<UL>
START:index
	<LI> <OBJECT type="text/sitemap">
		<param name="Name" value="%name%">
		<param name="Local" value="%aref%">
		</OBJECT>
END:index
</UL>
</BODY></HTML>
}
end
end
