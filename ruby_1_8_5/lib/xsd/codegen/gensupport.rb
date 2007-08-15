# XSD4R - Code generation support
# Copyright (C) 2004, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


module XSD
module CodeGen

# from the file 'keywords' in 1.9.
KEYWORD = {}
%w(
__LINE__
__FILE__
BEGIN
END
alias
and
begin
break
case
class
def
defined?
do
else
elsif
end
ensure
false
for
if
in
module
next
nil
not
or
redo
rescue
retry
return
self
super
then
true
undef
unless
until
when
while
yield
).each { |k| KEYWORD[k] = nil }

module GenSupport
  def capitalize(target)
    target.sub(/^([a-z])/) { $1.tr!('[a-z]', '[A-Z]') }
  end
  module_function :capitalize

  def uncapitalize(target)
    target.sub(/^([A-Z])/) { $1.tr!('[A-Z]', '[a-z]') }
  end
  module_function :uncapitalize

  def safeconstname(name)
    safename = name.scan(/[a-zA-Z0-9_]+/).collect { |ele|
      GenSupport.capitalize(ele)
    }.join
    if /^[A-Z]/ !~ safename or keyword?(safename)
      safename = "C_#{safename}"
    end
    safename
  end
  module_function :safeconstname

  def safeconstname?(name)
    /\A[A-Z][a-zA-Z0-9_]*\z/ =~ name and !keyword?(name)
  end
  module_function :safeconstname?

  def safemethodname(name)
    safename = name.scan(/[a-zA-Z0-9_]+/).join('_')
    safename = uncapitalize(safename)
    if /^[a-z]/ !~ safename
      safename = "m_#{safename}"
    end
    safename
  end
  module_function :safemethodname

  def safemethodname?(name)
    /\A[a-zA-Z_][a-zA-Z0-9_]*[=!?]?\z/ =~ name
  end
  module_function :safemethodname?

  def safevarname(name)
    safename = uncapitalize(name.scan(/[a-zA-Z0-9_]+/).join('_'))
    if /^[a-z]/ !~ safename or keyword?(safename)
      "v_#{safename}"
    else
      safename
    end
  end
  module_function :safevarname

  def safevarname?(name)
    /\A[a-z_][a-zA-Z0-9_]*\z/ =~ name and !keyword?(name)
  end
  module_function :safevarname?

  def keyword?(word)
    KEYWORD.key?(word)
  end
  module_function :keyword?

  def format(str, indent = nil)
    str = trim_eol(str)
    str = trim_indent(str)
    if indent
      str.gsub(/^/, " " * indent)
    else
      str
    end
  end

private

  def trim_eol(str)
    str.collect { |line|
      line.sub(/\r?\n\z/, "") + "\n"
    }.join
  end

  def trim_indent(str)
    indent = nil
    str = str.collect { |line| untab(line) }.join
    str.each do |line|
      head = line.index(/\S/)
      if !head.nil? and (indent.nil? or head < indent)
        indent = head
      end
    end
    return str unless indent
    str.collect { |line|
      line.sub(/^ {0,#{indent}}/, "")
    }.join
  end

  def untab(line, ts = 8)
    while pos = line.index(/\t/)
      line = line.sub(/\t/, " " * (ts - (pos % ts)))
    end
    line
  end

  def dump_emptyline
    "\n"
  end
end


end
end
