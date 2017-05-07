module FileSpecs
  # Try to set up known locations of each filetype
  def self.reconfigure()
    @file   = tmp("test.txt")
    @dir    = Dir.pwd
    @fifo   = tmp("test_fifo")

    platform_is_not :windows do
      @block  = `find /dev /devices -type b 2> /dev/null`.split("\n").first
      @char   = `find /dev /devices -type c 2> /dev/null`.split("\n").last

      %w[/dev /usr/bin /usr/local/bin].each do |dir|
        links = `find #{dir} -type l 2> /dev/null`.split("\n")
        next if links.empty?
        @link = links.first
        break
      end

    end
  end

  # TODO: Automatic reload mechanism
  reconfigure

  def self.normal_file()
    File.open(@file, "w") {} # 'Touch'
    yield @file
  ensure
    rm_r @file
  end

  def self.directory()
    yield @dir
  end

  # TODO: need a platform-independent helper here
  def self.fifo()
    system "mkfifo #{@fifo} 2> /dev/null"
    yield @fifo
  ensure
    rm_r @fifo
  end

  def self.block_device()
    yield @block
  end

  def self.character_device()
    yield @char
  end

  def self.symlink()
    yield @link
  end

  def self.socket()
    require 'socket'
    name = tmp("ftype_socket.socket")
    rm_r name
    socket = UNIXServer.new name
    yield name
    socket.close
    rm_r name
  end
end
