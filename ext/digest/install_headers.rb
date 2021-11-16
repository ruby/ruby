require "fileutils"

*files, dest = ARGV

if File.exist?(File.join(dest, "ruby.h"))
  warn "installing header files"

  files.each { |file|
    FileUtils.install file, dest, mode: 0644, verbose: true
  }
else
  warn "not installing header files when installed as an external library"
end
