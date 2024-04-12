#include "regenc.h"
/* dummy for unsupported, non-ascii-based encoding */
ENC_DUMMY("IBM037");
ENC_ALIAS("ebcdic-cp-us", "IBM037");

/* we start with just defining a single EBCDIC encoding,
 * hopefully the most widely used one.
 *
 * See http://www.iana.org/assignments/character-sets/character-sets.xhtml
 *     https://www.rfc-editor.org/rfc/rfc1345
 */
