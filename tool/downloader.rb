require 'open-uri'

class Downloader
  def self.download(url, name, dir = nil)
    data = URI(url).read
    file = dir ? File.join(dir, name) : name
    open(file, "wb", 0755) {|f| f.write(data)}
  rescue => e
    raise "failed to download #{name}\n#{e.message}: #{uri}"
  end
end
