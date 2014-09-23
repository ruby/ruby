require 'open-uri'

class Downloader
  def self.download(url, name, dir = nil)
    data = URI(url).read
    file = dir ? File.join(dir, name) : name
    open(file, "wb", 0755) {|f| f.write(data)}
  rescue => e
    raise "failed to download #{name}\n#{e.message}: #{url}"
  end

  # Update a file from url if newer version is available.
  # Creates the file if the file doesn't yet exist; however, the
  # directory where the file is being created has to exist already.
  # Example usage:
  #   download_if_modified_since 'http://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt',
  #           'enc/unicode/data/UnicodeData.txt'
  def self.download_if_modified_since(url, name, dir=nil, since=nil)
    file = dir ? File.join(dir, name) : name
    since = Date.new(1980,1,1) unless File.exist? file            # use very old date to assure file creation
    since = File.mtime file    unless since                       # get last modification time for file
    since = since.to_datetime   if since.respond_to? :to_datetime # convert Time/Date to DateTime
    since = since.httpdate      if since.respond_to? :httpdate    # convert DateTime to String
    open(url, 'If-Modified-Since' => since) do |r|
      body = r.read
      open(file, 'wb', 0755) { |f| f.write(body) }
    end
  rescue OpenURI::HTTPError => http_error
    unless http_error.message =~ /^304 / # 304 Not Modified
      raise "Failed to (check for) downloading #{url}: #{http_error.message}"
    end
  end
end
