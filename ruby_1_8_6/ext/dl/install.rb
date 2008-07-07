require 'mkmf'
require 'ftools'

SO_LIBS = ["dl.so"]

$ruby_version = CONFIG['MAJOR'] + "." + CONFIG['MINOR']
$prefix = CONFIG['prefix']
$libdir = File.join($prefix,'lib')
$rubylibdir = File.join($libdir, 'ruby', $ruby_version)
$arch = CONFIG['arch']
$archdir = File.join($rubylibdir, $arch)

def find(dir, match = /./)
  Dir.chdir(dir)
  files = []
  Dir.new(".").each{|file|
    if( file != "." && file != ".." )
      case File.ftype(file)
      when "file"
	if( file =~ match )
	  files.push(File.join(dir,file))
	end
      when "directory"
	files += find(file, match).collect{|f| File.join(dir,f)}
      end
    end
  }
  Dir.chdir("..")
  return files
end

def install()
  rb_files = find(File.join(".","lib"), /.rb$/)

  SO_LIBS.each{|f|
    File.makedirs($rubylibdir, "#{$archdir}")
    File.install(f, File.join($archdir,f), 0555, true)
  }

  rb_files.each{|f|
    origfile = f
    instfile = File.join($rubylibdir, origfile.sub("./lib/",""))
    instdir  = File.dirname(instfile)
    File.makedirs(instdir)
    File.install(origfile, instfile, 0644, true)
  }
end

install()
