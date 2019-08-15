module FileSpecs
  def self.configure_types
    return if @configured

    @file   = tmp("test.txt")
    @dir    = Dir.pwd
    @fifo   = tmp("test_fifo")
    @link   = tmp("test_link")

    platform_is_not :windows do
      @block  = `find /dev /devices -type b 2>/dev/null`.split("\n").first
      @char   = `{ tty || find /dev /devices -type c; } 2>/dev/null`.split("\n").last
    end

    @configured = true
  end

  def self.normal_file
    touch(@file)
    yield @file
  ensure
    rm_r @file
  end

  def self.directory
    yield @dir
  end

  def self.fifo
    File.mkfifo(@fifo)
    yield @fifo
  ensure
    rm_r @fifo
  end

  def self.block_device
    raise "Could not find a block device" unless @block
    yield @block
  end

  def self.character_device
    raise "Could not find a character device" unless @char
    yield @char
  end

  def self.symlink
    touch(@file)
    File.symlink(@file, @link)
    yield @link
  ensure
    rm_r @file, @link
  end

  def self.socket
    require_relative '../../../library/socket/fixtures/classes.rb'

    name = SocketSpecs.socket_path
    socket = UNIXServer.new name
    begin
      yield name
    ensure
      socket.close
      rm_r name
    end
  end
end
