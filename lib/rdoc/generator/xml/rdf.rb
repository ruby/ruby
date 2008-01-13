require 'rdoc/generator/xml'

module RDoc::Generator::XML::RDF

  CONTENTS_RDF = <<-EOF
<% if defined? classes and classes["description"] then %>
    <description rd:parseType="Literal">
<%= classes["description"] %>
    </description>
<% end %>

<% if defined? files and files["requires"] then %>
<% files["requires"].each do |requires| %>
         <rd:required-file rd:name="<%= requires["name"] %>" />
<% end # files["requires"] %>
<% end %>

<% if defined? classes and classes["includes"] then %>
      <IncludedModuleList>
<% classes["includes"].each do |includes| %>
        <included-module rd:name="<%= includes["name"] %>"  />
<% end # includes["includes"] %>
      </IncludedModuleList>
<% end %>

<% if defined? classes and classes["sections"] then %>
<% classes["sections"].each do |sections| %>
<% if sections["attributes"] then %>
<% sections["attributes"].each do |attributes| %>
        <contents>
        <Attribute rd:name="<%= attributes["name"] %>">
<% if attributes["rw"] then %>
          <attribute-rw><%= attributes["rw"] %></attribute-rw>
<% end %>
          <description rdf:parseType="Literal"><%= attributes["a_desc"] %></description>
        </Attribute>
        </contents>
<% end # sections["attributes"] %>
<% end %>

<% if sections["method_list"] then %>
<% sections["method_list"].each do |method_list| %>
<% if method_list["methods"] then %>
<% method_list["methods"].each do |methods| %>
	<contents>
        <Method rd:name="<%= methods["name"] %>" rd:visibility="<%= methods["type"] %>"
                rd:category="<%= methods["category"] %>" rd:id="<%= methods["aref"] %>">
          <parameters><%= methods["params"] %></parameters>
<% if methods["m_desc"] then %>
          <description rdf:parseType="Literal">
<%= methods["m_desc"] %>
          </description>
<% end %>
<% if methods["sourcecode"] then %>
          <source-code-listing rdf:parseType="Literal">
<%= methods["sourcecode"] %>
          </source-code-listing>
<% end %>
        </Method>
       </contents>
<% end # method_list["methods"] %>
<% end %>
<% end # sections["method_list"] %>
<% end %>
     <!-- end method list -->
<% end # classes["sections"] %>
<% end %>
  EOF

########################################################################

  ONE_PAGE = %{<?xml version="1.0" encoding="utf-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        xmlns="http://pragprog.com/rdoc/rdoc.rdf#"
        xmlns:rd="http://pragprog.com/rdoc/rdoc.rdf#">

<!-- RDoc -->
<% values["files"].each do |files| %>
  <rd:File rd:name="<%= files["short_name"] %>" rd:id="<%= files["href"] %>">
      <path><%= files["full_path"] %></path>
      <dtm-modified><%= files["dtm_modified"] %></dtm-modified>
} + CONTENTS_RDF + %{
  </rd:File>
<% end # values["files"] %>
<% values["classes"].each do |classes| %>
  <<%= values["classmod"] %> rd:name="<%= classes["full_name"] %>" rd:id="<%= classes["full_name"] %>">
    <classmod-info>
<% if classes["infiles"] then %>
      <InFiles>
<% classes["infiles"].each do |infiles| %>
        <infile>
          <File rd:name="<%= infiles["full_path"] %>"
<% if infiles["full_path_url"] then %>
                rdf:about="<%= infiles["full_path_url"] %>"
<% end %>
           />
         </infile>
<% end # classes["infiles"] %>
      </InFiles>
<% end %>
<% if classes["parent"] then %>
     <superclass><%= href classes["par_url"], classes["parent"] %></superclass>
<% end %>
    </classmod-info>
} + CONTENTS_RDF + %{
  </<%= classes["classmod"] %>>
<% end # values["classes"] %>
<!-- /RDoc -->
</rdf:RDF>
}

end

