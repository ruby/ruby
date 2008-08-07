#include "transcode_data.h"

<%
  require 'sjis-tbl'
  require 'eucjp-tbl'
%>

<%= transcode_tblgen "Shift_JIS", "UTF-8", [["{00-7f}", :nomap], *SJIS_TO_UCS_TBL] %>
<%= transcode_tblgen "Windows-31J", "UTF-8", [["{00-7f}", :nomap], *SJIS_TO_UCS_TBL] %>

<%= transcode_tblgen "UTF-8", "Shift_JIS", [["{00-7f}", :nomap], *UCS_TO_SJIS_TBL] %>
<%= transcode_tblgen "UTF-8", "Windows-31J", [["{00-7f}", :nomap], *UCS_TO_SJIS_TBL] %>

<%= transcode_tblgen "EUC-JP", "UTF-8", [["{00-7f}", :nomap], *EUCJP_TO_UCS_TBL] %>
<%= transcode_tblgen "CP51932", "UTF-8", [["{00-7f}", :nomap], *EUCJP_TO_UCS_TBL] %>

<%= transcode_tblgen "UTF-8", "EUC-JP", [["{00-7f}", :nomap], *UCS_TO_EUCJP_TBL] %>
<%= transcode_tblgen "UTF-8", "CP51932", [["{00-7f}", :nomap], *UCS_TO_EUCJP_TBL] %>

void
Init_japanese(void)
{
<%= transcode_register_code %>
}
