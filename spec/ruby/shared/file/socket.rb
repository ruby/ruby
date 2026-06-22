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
end
