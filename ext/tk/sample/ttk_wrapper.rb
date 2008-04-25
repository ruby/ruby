#!/usr/bin/env ruby
#
#  ttk_wrapper.rb  --  use Ttk widgets as default on old Ruby/Tk scripts
#
#                       by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
version = '0.1.1'
#
##########################################################################
#  parse commandline arguments
##########################################################################
require 'optparse'
opt = OptionParser.new("Usage: #{$0} [options] rubytk_script" << "\n    " << 
                         "Ruby/Tk script wrapper. Use Ttk widgets as default.")
opt.version = version

OPTS = {}
OPTS[:themedir] = []
OPTS[:rb_theme] = []
OPTS[:theme] = 'default'

opt.on('-l', '--list', 'list available theme names'){|v| OPTS[:list] = true}
opt.on('-t', '--theme theme', 'theme name'){|v| OPTS[:theme] = v}
opt.on('-d', '--themedir themes_dir', 'directory of theme definitions'){|v| 
  OPTS[:themedir] << v
}
opt.on('-r', '--rubytheme rb_theme', 'theme definition file (ruby script)'){|v|
  OPTS[:rb_theme] << v
}
opt.on('-v', '--verbose', 'print verbose messages'){|v| OPTS[:verbose] = true}

opt.parse!(ARGV)


##########################################################################
#  load Ttk (Tile) extension
##########################################################################
require 'tk'

begin
  require 'tkextlib/tile'
  Tk.default_widget_set = :Ttk
rescue LoadError
  if OPTS[:verbose]
    print "warning: fail to load 'Ttk' extension. use standard widgets.\n" 
  end
end

if OPTS[:verbose]
  print "current default widget set is '#{Tk.default_widget_set}'\n"
end


##########################################################################
# define Tcl/Tk procedures for compatibility.
# those are required when want to use themes included 
# in "sample/tkextlib/tile/demo.rb".
##########################################################################
Tk::Tile.__define_LoadImages_proc_for_compatibility__!
Tk::Tile::Style.__define_wrapper_proc_for_compatibility__!


##########################################################################
#  use themes defined on the demo of Ttk (Tile) extension
##########################################################################
demodir = File.dirname(__FILE__)
demo_themesdir = File.expand_path(File.join(demodir, 'tkextlib', 'tile', 'themes'))

Tk::AUTO_PATH.lappend(*OPTS[:themedir]) unless OPTS[:themedir].empty?
Tk::AUTO_PATH.lappend('.', demodir, demo_themesdir)

OPTS[:themedir] << demo_themesdir
print "theme-dirs: #{OPTS[:themedir].inspect}\n" if OPTS[:verbose]

OPTS[:themedir].each{|themesdir|
  if File.directory?(themesdir)
    Dir.foreach(themesdir){|name|
      next if name == '.' || name == '..'
      path = File.join(themesdir, name)
      Tk::AUTO_PATH.lappend(path) if File.directory?(path)
    }
  end
}

# This forces an update of the available packages list. It's required
# for package names to find the themes in demos/themes/*.tcl
Tk.ip_eval("#{TkPackage.unknown_proc}  Tcl #{TkPackage.provide('Tcl')}")

# load themes written in Ruby.
themes_by_ruby = [File.join(demo_themesdir, 'kroc.rb')]
themes_by_ruby.concat OPTS[:rb_theme]
print "ruby-themes: #{themes_by_ruby.inspect}\n" if OPTS[:verbose]

themes_by_ruby.each{|f|
  begin
    load(f, true)
  rescue LoadError
    print "fail to load \"#{f}\"\n" if OPTS[:verbose]
  end
}


##########################################################################
# ignore unsupported options of Ttk widgets
##########################################################################
TkConfigMethod.__set_IGNORE_UNKNOWN_CONFIGURE_OPTION__! true
TkItemConfigMethod.__set_IGNORE_UNKNOWN_CONFIGURE_OPTION__! true


##########################################################################
#  define utility method
##########################################################################
def setTheme(theme)
  unless Tk::Tile::Style.theme_names.find{|n| n == theme}
    if (pkg = TkPackage.names.find{|n| n =~ /(tile|ttk)::theme::#{theme}/})
      TkPackage.require(pkg)
    end
  end
  Tk::Tile::Style.theme_use(theme)
end


##########################################################################
#  make theme name list
##########################################################################
ThemesList = Tk::Tile::Style.theme_names
TkPackage.names.find_all{|n| n =~ /^(tile|ttk)::theme::/}.each{|pkg|
  ThemesList << pkg.split('::')[-1]
}
ThemesList.uniq!


##########################################################################
#  set theme of widget style
##########################################################################
if OPTS[:list] || OPTS[:verbose]
  print "supported theme names: #{ThemesList.inspect}\n" 
  exit if OPTS[:list] && ARGV.empty?
end
print "use theme: \"#{OPTS[:theme]}\"\n" if OPTS[:theme] && OPTS[:verbose]
setTheme(OPTS[:theme]) if OPTS[:theme]


##########################################################################
#  load script
##########################################################################
if (path = ARGV.shift) && (script = File.expand_path(path))
  print "load script \"#{script}\"\n" if OPTS[:verbose]
  load(script)
else
  print "Error: no script is given.\n"
  print opt.help
  exit(1)
end
