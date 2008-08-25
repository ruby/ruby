#include "transcode_data.h"

<%
  us_ascii_map = [["{00-7f}", :nomap], ["{80-ff}", :undef]]

  ISO_8859_1_TO_UCS_TBL = (0x80..0xff).map {|c| ["%02X" % c, c] }
  CONTROL1_TO_UCS_TBL = (0x80..0x9f).map {|c| ["%02X" % c, c] }

  require 'iso-8859-2-tbl'
  require 'iso-8859-3-tbl'
  require 'iso-8859-4-tbl'
  require 'iso-8859-5-tbl'
  require 'iso-8859-6-tbl'
  require 'iso-8859-7-tbl'
  require 'iso-8859-8-tbl'
  require 'iso-8859-9-tbl'
  require 'iso-8859-10-tbl'
  require 'iso-8859-11-tbl'
  require 'iso-8859-13-tbl'
  require 'iso-8859-14-tbl'
  require 'iso-8859-15-tbl'

%>

<%= transcode_tblgen "US-ASCII", "UTF-8", us_ascii_map %>
<%= transcode_tblgen "UTF-8", "US-ASCII", us_ascii_map %>
<%= transcode_tblgen "ASCII-8BIT", "UTF-8", us_ascii_map %>
<%= transcode_tblgen "UTF-8", "ASCII-8BIT", us_ascii_map %>

<%
  def transcode_tblgen_iso8859(name, tbl_to_ucs)
    tbl_to_ucs = CONTROL1_TO_UCS_TBL + tbl_to_ucs
    name_ident = name.tr('-','_')
    code = ''
    code << transcode_tblgen(name, "UTF-8", [["{00-7f}", :nomap], *tbl_to_ucs])
    code << "\n"
    code << transcode_tblgen("UTF-8", name, [["{00-7f}", :nomap], *tbl_to_ucs.map {|a,b| [b,a] }])
    code
  end
%>

<%= transcode_tblgen_iso8859("ISO-8859-1", ISO_8859_1_TO_UCS_TBL) %>
<%= transcode_tblgen_iso8859("ISO-8859-2", ISO_8859_2_TO_UCS_TBL) %>
<%= transcode_tblgen_iso8859("ISO-8859-3", ISO_8859_3_TO_UCS_TBL) %>
<%= transcode_tblgen_iso8859("ISO-8859-4", ISO_8859_4_TO_UCS_TBL) %>
<%= transcode_tblgen_iso8859("ISO-8859-5", ISO_8859_5_TO_UCS_TBL) %>
<%= transcode_tblgen_iso8859("ISO-8859-6", ISO_8859_6_TO_UCS_TBL) %>
<%= transcode_tblgen_iso8859("ISO-8859-7", ISO_8859_7_TO_UCS_TBL) %>
<%= transcode_tblgen_iso8859("ISO-8859-8", ISO_8859_8_TO_UCS_TBL) %>
<%= transcode_tblgen_iso8859("ISO-8859-9", ISO_8859_9_TO_UCS_TBL) %>
<%= transcode_tblgen_iso8859("ISO-8859-10", ISO_8859_10_TO_UCS_TBL) %>
<%= transcode_tblgen_iso8859("ISO-8859-11", ISO_8859_11_TO_UCS_TBL) %>
<%= transcode_tblgen_iso8859("ISO-8859-13", ISO_8859_13_TO_UCS_TBL) %>
<%= transcode_tblgen_iso8859("ISO-8859-14", ISO_8859_14_TO_UCS_TBL) %>
<%= transcode_tblgen_iso8859("ISO-8859-15", ISO_8859_15_TO_UCS_TBL) %>

void
Init_single_byte(void)
{
<%= transcode_register_code %>
}

