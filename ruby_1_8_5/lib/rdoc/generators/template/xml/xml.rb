module RDoc
module Page



CONTENTS_XML = %{
IF:description
    <description>
%description%
    </description>
ENDIF:description
    <contents>
IF:requires
      <required-file-list>
START:requires
         <required-file name="%name%"
IF:aref 
                        href="%aref%"
ENDIF:aref
         />
END:requires
      </required-file-list>
ENDIF:requires
IF:attributes
      <attribute-list>
START:attributes
        <attribute name="%name%">
IF:rw
          <attribute-rw>%rw%</attribute-rw>
ENDIF:rw
          <description>%a_desc%</description>
        </attribute>
END:attributes
      </attribute-list>
ENDIF:attributes
IF:includes
      <included-module-list>
START:includes
        <included-module name="%name%"
IF:aref
                         href="%aref%"
ENDIF:aref
        />
END:includes
      </included-module-list>
ENDIF:includes
IF:method_list
      <method-list>
START:method_list
IF:methods
START:methods
        <method name="%name%" type="%type%" category="%category%" id="%aref%">
          <parameters>%params%</parameters>
IF:m_desc
          <description>
%m_desc%
          </description>
ENDIF:m_desc
IF:sourcecode
          <source-code-listing>
%sourcecode%
          </source-code-listing>
ENDIF:sourcecode
        </method>
END:methods
ENDIF:methods
END:method_list
      </method-list>
ENDIF:method_list
     </contents>
}

########################################################################

ONE_PAGE = %{<?xml version="1.0" encoding="utf-8"?>
<rdoc>
<file-list>
START:files
  <file name="%short_name%" id="%href%">
    <file-info>
      <path>%full_path%</path>
      <dtm-modified>%dtm_modified%</dtm-modified>
    </file-info>
} + CONTENTS_XML + %{
  </file>
END:files
</file-list>
<class-module-list>
START:classes
  <%classmod% name="%full_name%" id="%full_name%">
    <classmod-info>
IF:infiles
      <infiles>      
START:infiles
        <infile>HREF:full_path_url:full_path:</infile>
END:infiles
      </infiles>
ENDIF:infiles
IF:parent
     <superclass>HREF:par_url:parent:</superclass>
ENDIF:parent
    </classmod-info>
} + CONTENTS_XML + %{
  </%classmod%>
END:classes
</class-module-list>
</rdoc>
}


end
end
