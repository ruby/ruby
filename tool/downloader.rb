require 'open-uri'

class Downloader
  def self.mode_for(data)
    data.start_with?("#!") ? 0755 : 0644
  end

  def self.http_options(file, since)
    options = {}
    if since
      case since
      when true
        since = (File.mtime(file).httpdate rescue nil)
      when Time
        since = since.httpdate
      end
      if since
        options['If-Modified-Since'] = since
      end
    end
    options
  end

  # Downloader.download(url, name, [dir, [ims]])
  #
  # Update a file from url if newer version is available.
  # Creates the file if the file doesn't yet exist; however, the
  # directory where the file is being created has to exist already.
  # If +ims+ is false, already download url regardless its last
  # modified time.
  #
  # Example usage:
  #   download 'http://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt',
  #           'enc/unicode/data/UnicodeData.txt'
  def self.download(url, name, dir = nil, ims = true)
    file = dir ? File.join(dir, name) : name
    url = URI(url)
    begin
      data = url.read(http_options(file, ims))
    rescue OpenURI::HTTPError => http_error
      return http_error.message =~ /^304 / # 304 Not Modified
      raise
    end
    mtime = nil
    open(file, "wb", 0600) do |f|
      f.write(data)
      f.chmod(mode_for(data))
      mtime = data.meta["last-modified"]
    end
    if mtime
      mtime = Time.httpdate(mtime)
      File.utime(mtime, mtime, file)
    end
    true
  rescue => e
    raise "failed to download #{name}\n#{e.message}: #{url}"
  end

  def self.download_if_modified_since(url, name, dir = nil)
    download(url, name, dir)
  end
end
