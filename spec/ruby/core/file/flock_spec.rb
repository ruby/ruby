require_relative '../../spec_helper'

describe "File#flock" do
  before :each do
    ScratchPad.record []

    @name = tmp("flock_test")
    touch(@name)

    @file = File.open @name, "w+"
  end

  after :each do
    @file.flock File::LOCK_UN
    @file.close

    rm_r @name
  end

  it "exclusively locks a file" do
    @file.flock(File::LOCK_EX).should == 0
    @file.flock(File::LOCK_UN).should == 0
  end

  it "non-exclusively locks a file" do
    @file.flock(File::LOCK_SH).should == 0
    @file.flock(File::LOCK_UN).should == 0
  end

  it "returns false if trying to lock an exclusively locked file" do
    @file.flock File::LOCK_EX

    ruby_exe(<<-END_OF_CODE).should == "false"
      File.open('#{@name}', "w") do |f2|
        print f2.flock(File::LOCK_EX | File::LOCK_NB).to_s
      end
    END_OF_CODE
  end

  it "blocks if trying to lock an exclusively locked file" do
    @file.flock File::LOCK_EX

    out = ruby_exe(<<-END_OF_CODE)
      running = false

      t = Thread.new do
        File.open('#{@name}', "w") do |f2|
          puts "before"
          running = true
          f2.flock(File::LOCK_EX)
          puts "after"
        end
      end

      Thread.pass until running
      Thread.pass while t.status and t.status != "sleep"
      sleep 0.1

      t.kill
      t.join
    END_OF_CODE

    out.should == "before\n"
  end

  it "returns 0 if trying to lock a non-exclusively locked file" do
    @file.flock File::LOCK_SH

    File.open(@name, "r") do |f2|
      f2.flock(File::LOCK_SH | File::LOCK_NB).should == 0
      f2.flock(File::LOCK_UN).should == 0
    end
  end
end
