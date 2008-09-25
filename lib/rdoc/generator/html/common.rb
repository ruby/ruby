#
# The templates require further refactoring.  In particular,
# * Some kind of HTML generation library should be used.
#
# Also, all of the templates require some TLC from a designer.
#
# Right now, this file contains some constants that are used by all
# of the templates.
#
module RDoc::Generator::HTML::Common
  XHTML_STRICT_PREAMBLE = <<-EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
EOF

  XHTML_FRAME_PREAMBLE = <<-EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Frameset//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd">
EOF

  HTML_ELEMENT = <<-EOF
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
EOF
end
