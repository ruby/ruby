#!./miniruby

def create_gsub_rb()
  f = open("mswin32_gsub.rb", "w")
  has_version = false
  f.print 'f = open("extmk.rb", "w")', "\n"
  f.print 'File.foreach "extmk.rb.in" do |$_|', "\n"
  File.foreach "../config.status" do |$_|
    next if /^#/
    if /^s%@(\w+)@%(.*)%g/
      name = $1
      val = $2 || ""
      next if name =~ /^(INSTALL|DEFS|configure_input|srcdir)$/
      val = ".." if name == "top_srcdir"
      val.gsub!(/\$\{([^{}]+)\}/) { "$(#{$1})" }
      f.print "  gsub!(\"@#{name}@\", \"#{val}\")\n"
      has_version = true if name == "MAJOR"
    end
  end
  
  if not has_version
    VERSION.scan(/(\d+)\.(\d+)\.(\d+)/) {
      f.print "  gsub!(\"@MAJOR@\", \"#{$1}\")\n"
      f.print "  gsub!(\"@MINOR@\", \"#{$2}\")\n"
      f.print "  gsub!(\"@TEENY@\", \"#{$3}\")\n"
    }
  end
  f.print '  f.print $_', "\n"
  f.print 'end', "\n"
  f.print 'f.close', "\n"
  f.close
end

begin
  create_gsub_rb()
  load "mswin32_gsub.rb"
ensure
  File.unlink "mswin32_gsub.rb"
end

# vi:set sw=2:
