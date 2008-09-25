require 'rdoc/generator/xml'

module RDoc::Generator::XML::XML

  CONTENTS_XML = <<-EOF
<% if defined? classes and classes["description"] then %>
    <description>
<%= classes["description"] %>
    </description>
<% end %>
    <contents>
<% if defined? files and files["requires"] then %>
      <required-file-list>
<% files["requires"].each do |requires| %>
         <required-file name="<%= requires["name"] %>"
<% if requires["aref"] then %>
                        href="<%= requires["aref"] %>"
<% end %>
         />
<% end %><%# files["requires"] %>
      </required-file-list>
<% end %>
<% if defined? classes and classes["sections"] then %>
<% classes["sections"].each do |sections| %>
<% if sections["constants"] then %>
      <constant-list>
<% sections["constants"].each do |constant| %>
        <constant name="<%= constant["name"] %>">
<% if constant["value"] then %>
          <value><%= constant["value"] %></value>
<% end %>
          <description><%= constant["a_desc"] %></description>
        </constant>
<% end %><%# sections["constants"] %>
      </constant-list>
<% end %>
<% if sections["attributes"] then %>
      <attribute-list>
<% sections["attributes"].each do |attributes| %>
        <attribute name="<%= attributes["name"] %>">
<% if attributes["rw"] then %>
          <attribute-rw><%= attributes["rw"] %></attribute-rw>
<% end %>
          <description><%= attributes["a_desc"] %></description>
        </attribute>
<% end %><%# sections["attributes"] %>
      </attribute-list>
<% end %>
<% if sections["method_list"] then %>
      <method-list>
<% sections["method_list"].each do |method_list| %>
<% if method_list["methods"] then %>
<% method_list["methods"].each do |methods| %>
        <method name="<%= methods["name"] %>" type="<%= methods["type"] %>" category="<%= methods["category"] %>" id="<%= methods["aref"] %>">
          <parameters><%= methods["params"] %></parameters>
<% if methods["m_desc"] then %>
          <description>
<%= methods["m_desc"] %>
          </description>
<% end %>
<% if methods["sourcecode"] then %>
          <source-code-listing>
<%= methods["sourcecode"] %>
          </source-code-listing>
<% end %>
        </method>
<% end %><%# method_list["methods"] %>
<% end %>
<% end %><%# sections["method_list"] %>
      </method-list>
<% end %>
<% end %><%# classes["sections"] %>
<% end %>
<% if defined? classes and classes["includes"] then %>
      <included-module-list>
<% classes["includes"].each do |includes| %>
        <included-module name="<%= includes["name"] %>"
<% if includes["aref"] then %>
                         href="<%= includes["aref"] %>"
<% end %>
        />
<% end %><%# classes["includes"] %>
      </included-module-list>
<% end %>
    </contents>
  EOF

  ONE_PAGE = %{<?xml version="1.0" encoding="utf-8"?>
<rdoc>
<file-list>
<% values["files"].each do |files| %>
  <file name="<%= files["short_name"] %>" id="<%= files["href"] %>">
    <file-info>
      <path><%= files["full_path"] %></path>
      <dtm-modified><%= files["dtm_modified"] %></dtm-modified>
    </file-info>
} + CONTENTS_XML + %{
  </file>
<% end %><%# values["files"] %>
</file-list>
<class-module-list>
<% values["classes"].each do |classes| %>
  <<%= classes["classmod"] %> name="<%= classes["full_name"] %>" id="<%= classes["full_name"] %>">
    <classmod-info>
<% if classes["infiles"] then %>
      <infiles>
<% classes["infiles"].each do |infiles|  %>
        <infile><%= href infiles["full_path_url"], infiles["full_path"] %></infile>
<% end %><%# classes["infiles"] %>
      </infiles>
<% end %>
<% if classes["parent"] then %>
     <superclass><%= href classes["par_url"], classes["parent"] %></superclass>
<% end %>
    </classmod-info>
} + CONTENTS_XML + %{
  </<%= classes["classmod"] %>>
<% end %><%# values["classes"] %>
</class-module-list>
</rdoc>
}

end
