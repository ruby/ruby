#!./miniruby -sI.

require 'rbconfig'

CONFIG = Config::MAKEFILE_CONFIG

fversion = "#{CONFIG['MAJOR']},#{CONFIG['MINOR']},#{CONFIG['TEENY']},0"

$ruby_name ||= CONFIG["RUBY_INSTALL_NAME"]
$rubyw_name ||= CONFIG["RUBYW_INSTALL_NAME"] || $ruby_name.sub(/ruby/, '\&w')
$so_name ||= CONFIG["RUBY_SO_NAME"]

icons = {}
def icons.find(path)
  if File.directory?(path)
    Dir.open(File.expand_path(path)) do |d|
      d.grep(/\.ico$/i) {|i| self[$`] = i}
    end
  else
    self[File.basename(path, '.ico')] = path
  end
  self
end

if ARGV.empty?
  icons.find('.')
else
  ARGV.each {|i| icons.find(i)}
end

ruby_icon = rubyw_icon = nil
[$ruby_name, 'ruby'].each do |i|
  if i = icons[i]
    ruby_icon = "1 ICON DISCARDABLE "+i.dump+"\n"
    break
  end
end
[$rubyw_name, 'rubyw'].each do |i|
  if i = icons[i]
    rubyw_icon = "1 ICON DISCARDABLE "+i.dump+"\n"
    break
  end
end
dll_icons = []
icons.keys.sort.each do |i|
  dll_icons << "#{dll_icons.size + 1} ICON DISCARDABLE "+icons[i].dump+"\n"
end

[ # base name    extension         file type  icons
  [$ruby_name,   CONFIG["EXEEXT"], 'VFT_APP', ruby_icon],
  [$rubyw_name,  CONFIG["EXEEXT"], 'VFT_APP', rubyw_icon || ruby_icon],
  [$so_name,     '.dll',           'VFT_DLL', dll_icons],
].each do |base, ext, type, icons|
  open(base + '.rc', "w") { |f|
    f.binmode if /mingw/ =~ RUBY_PLATFORM

    f.print <<EOF
#ifndef __BORLANDC__
#include <windows.h>
#include <winver.h>
#endif

#{icons}
VS_VERSION_INFO VERSIONINFO
 FILEVERSION    #{fversion}
 PRODUCTVERSION #{fversion}
 FILEFLAGSMASK  0x3fL
 FILEFLAGS      0x0L
 FILEOS         VOS__WINDOWS32
 FILETYPE       #{type}
 FILESUBTYPE    VFT2_UNKNOWN
BEGIN
 BLOCK "StringFileInfo"
 BEGIN
  BLOCK "000004b0"
  BEGIN
   VALUE "FileDescription",  "Ruby interpreter\\0"
   VALUE "FileVersion",      "#{fversion}\\0"
   VALUE "Home Page",        "http://www.ruby-lang.org/\\0"
   VALUE "InternalName",     "#{base + ext}\\0"
   VALUE "LegalCopyright",   "Copyright (C) 1993-#{RUBY_RELEASE_DATE[/\d+/]} Yukihiro Matsumoto\\0"
   VALUE "OriginalFilename", "#{base + ext}\\0"
   VALUE "Platform",         "#{RUBY_PLATFORM}\\0"
   VALUE "ProductVersion",   "#{fversion}\\0"
   VALUE "Release Date",     "#{RUBY_RELEASE_DATE}\\0"
   VALUE "Version",          "#{RUBY_VERSION}\\0"
  END
 END
 BLOCK "VarFileInfo"
 BEGIN
  VALUE "Translation", 0x0, 0x4b0
 END
END
EOF
  }
end

