module RDoc::Page

require "rdoc/generators/template/html/html"

# This is a nasty little hack, but hhc doesn't support the <?xml
# tag, so...

BODY.sub!(/<\?xml.*\?>/, '')
SRC_PAGE.sub!(/<\?xml.*\?>/, '')

HPP_FILE = %{
[OPTIONS]
Auto Index = Yes
Compatibility=1.1 or later
Compiled file=<%= values["opname"] %>.chm
Contents file=contents.hhc
Full-text search=Yes
Index file=index.hhk
Language=0x409 English(United States)
Title=<%= values["title"] %>

[FILES]
<% values["all_html_files"].each do |all_html_files| %>
<%= all_html_files["html_file_name"] %>
<% end # values["all_html_files"] %>
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
<% values["contents"].each do |contents| %>
	<LI> <OBJECT type="text/sitemap">
		<param name="Name" value="<%= contents["c_name"] %>">
		<param name="Local" value="<%= contents["ref"] %>">
		</OBJECT>
<% if contents["methods"] then %>
<ul>
<% contents["methods"].each do |methods| %>
	<LI> <OBJECT type="text/sitemap">
		<param name="Name" value="<%= methods["name"] %>">
		<param name="Local" value="<%= methods["aref"] %>">
		</OBJECT>
<% end # contents["methods"] %>
</ul>
<% end %>
        </LI>
<% end # values["contents"] %>
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
<% values["index"].each do |index| %>
	<LI> <OBJECT type="text/sitemap">
		<param name="Name" value="<%= index["name"] %>">
		<param name="Local" value="<%= index["aref"] %>">
		</OBJECT>
<% end # values["index"] %>
</UL>
</BODY></HTML>
}

end

