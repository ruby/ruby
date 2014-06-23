require 'open-uri'

Downloader = "http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=%s;hb=HEAD"
def Downloader.download(name, dir = nil)
  uri = URI(self % name)
  data = uri.read
  file = dir ? File.join(dir, name) : name
  open(file, "wb", 0755) {|f| f.write(data)}
rescue => e
  raise "failed to download #{name}\n#{e.message}: #{uri}"
end
