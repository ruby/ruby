require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "Signal.[]" do
    before :each do
      @signal = Signal.list.key?("HUP") ? :HUP : :INT
      @signal_name = @signal.to_s
      @signal_number = Signal.list[@signal_name]
      @proc = -> {}
      @saved_trap = Signal.trap(@signal, @proc)
    end

    after :each do
      Signal.trap(@signal, @saved_trap)
    end

    it "returns the current handler" do
      Signal[@signal].should.equal?(@proc)
    end

    it "accepts signal names and numbers" do
      Signal[@signal_name].should.equal?(@proc)
      Signal[:"SIG#{@signal_name}"].should.equal?(@proc)
      Signal[@signal_number].should.equal?(@proc)
    end

    platform_is_not :windows do
      it "does not change the current handler" do
        done = false

        Signal.trap(@signal) do
          done = true
        end

        Signal[@signal].should.is_a?(Proc)

        Process.kill @signal, Process.pid
        Thread.pass until done
      end
    end

    it "returns nil for nil handlers" do
      Signal.trap(@signal, nil)
      Signal[@signal].should == nil
    end

    it "returns IGNORE for ignored signals" do
      Signal.trap(@signal, :IGNORE)
      Signal[@signal].should == "IGNORE"
    end

    it "returns DEFAULT for Ruby default handlers" do
      Signal.trap(@signal, :DEFAULT)
      Signal[@signal].should == "DEFAULT"
    end

    it "returns SYSTEM_DEFAULT for system default handlers" do
      Signal.trap(@signal, :SYSTEM_DEFAULT)
      Signal[@signal].should == "SYSTEM_DEFAULT"
    end

    it "returns the current EXIT handler" do
      handler = -> {}
      saved_trap = Signal.trap(:EXIT, handler)

      begin
        Signal[0].should.equal?(handler)
        Signal[:EXIT].should.equal?(handler)
      ensure
        Signal.trap(:EXIT, saved_trap || "DEFAULT")
      end
    end
  end
end
