describe :file_socket, shared: true do
  it "returns false if the file is not a socket" do
    filename = tmp("i_exist")
    touch(filename)

    @object.send(@method, filename).should == false

    rm_r filename
  end

  it "returns true if the file is a socket" do
    require 'socket'

    # We need a really short name here.
    # On Linux the path length is limited to 107, see unix(7).
    name = tmp("s")
    server = UNIXServer.new(name)

    @object.send(@method, name).should == true

    server.close
    rm_r name
  end

  it "accepts an object that has a #to_path method" do
    obj = Object.new
    def obj.to_path
      __FILE__
    end

    @object.send(@method, obj).should == false
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      utf8_path = tmp("utf8_path_\u{3042}.txt")
      # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
      non_utf8_path = utf8_path.encode(Encoding::Windows_31J)
      server = UNIXServer.new(utf8_path)

      begin
        @object.send(@method, non_utf8_path).should == true
      ensure
        server.close
        rm_r utf8_path
        rm_r non_utf8_path
      end
    end
  end
end
