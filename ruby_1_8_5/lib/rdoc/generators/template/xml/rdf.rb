module RDoc
module Page



CONTENTS_RDF = %{
IF:description
    <description rd:parseType="Literal">
%description%
    </description>
ENDIF:description

IF:requires
START:requires
         <rd:required-file rd:name="%name%" />
END:requires
ENDIF:requires

IF:attributes
START:attributes
        <contents>
        <Attribute rd:name="%name%">
IF:rw
          <attribute-rw>%rw%</attribute-rw>
ENDIF:rw
          <description rdf:parseType="Literal">%a_desc%</description>
        </Attribute>
        </contents>
END:attributes
ENDIF:attributes

IF:includes
      <IncludedModuleList>
START:includes
        <included-module rd:name="%name%"  />
END:includes
      </IncludedModuleList>
ENDIF:includes

IF:method_list
START:method_list
IF:methods
START:methods
	<contents>
        <Method rd:name="%name%" rd:visibility="%type%"
                rd:category="%category%" rd:id="%aref%">
          <parameters>%params%</parameters>
IF:m_desc
          <description rdf:parseType="Literal">
%m_desc%
          </description>
ENDIF:m_desc
IF:sourcecode
          <source-code-listing rdf:parseType="Literal">
%sourcecode%
          </source-code-listing>
ENDIF:sourcecode
        </Method>
       </contents>
END:methods
ENDIF:methods
END:method_list
ENDIF:method_list
     <!-- end method list -->
}

########################################################################

ONE_PAGE = %{<?xml version="1.0" encoding="utf-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        xmlns="http://pragprog.com/rdoc/rdoc.rdf#"
        xmlns:rd="http://pragprog.com/rdoc/rdoc.rdf#">

<!-- RDoc -->
START:files
  <rd:File rd:name="%short_name%" rd:id="%href%">
      <path>%full_path%</path>
      <dtm-modified>%dtm_modified%</dtm-modified>
} + CONTENTS_RDF + %{
  </rd:File>
END:files
START:classes
  <%classmod% rd:name="%full_name%" rd:id="%full_name%">
    <classmod-info>
IF:infiles
      <InFiles>
START:infiles
        <infile>
          <File rd:name="%full_path%"
IF:full_path_url
                rdf:about="%full_path_url%"
ENDIF:full_path_url
           />
         </infile>
END:infiles
      </InFiles>
ENDIF:infiles
IF:parent
     <superclass>HREF:par_url:parent:</superclass>
ENDIF:parent
    </classmod-info>
} + CONTENTS_RDF + %{
  </%classmod%>
END:classes
<!-- /RDoc -->
</rdf:RDF>
}


end
end

