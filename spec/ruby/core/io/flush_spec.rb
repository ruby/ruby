require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#flush" do
  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.flush }.should raise_error(IOError)
  end

  describe "on a pipe" do
    before :each do
      @r, @w = IO.pipe
    end

    after :each do
      @r.close
      begin
        @w.close
      rescue Errno::EPIPE
      end
    end

    # [ruby-core:90895] MJIT worker may leave fd open in a forked child.
    # For instance, MJIT creates a worker before @r.close with fork(), @r.close happens,
    # and the MJIT worker keeps the pipe open until the worker execve().
    # TODO: consider acquiring GVL from MJIT worker.
    guard_not -> { defined?(RubyVM::MJIT) && RubyVM::MJIT.enabled? } do
      it "raises Errno::EPIPE if sync=false and the read end is closed" do
        @w.sync = false
        @w.write "foo"
        @r.close

        -> { @w.flush }.should raise_error(Errno::EPIPE, /Broken pipe/)
        -> { @w.close }.should raise_error(Errno::EPIPE, /Broken pipe/)
      end
    end
  end
end
