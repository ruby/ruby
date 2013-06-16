require 'open-uri'

ConfigFiles = "http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=%s;hb=HEAD"
def ConfigFiles.download(name, dir = nil)
  data = URI.read(self % name)
  file = dir ? File.join(dir, name) : name
  open(file, "wb", 0755) {|f| f.write(data)}
end
