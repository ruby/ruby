require_relative '../../spec_helper'
require_relative 'shared/compose'

ruby_version_is "2.6" do
  describe "Proc#<<" do
    it "returns a Proc that is the composition of self and the passed Proc" do
      upcase = proc { |s| s.upcase }
      succ = proc { |s| s.succ }

      (succ << upcase).call('Ruby').should == "RUBZ"
    end

    it "calls passed Proc with arguments and then calls self with result" do
      f = proc { |x| x * x }
      g = proc { |x| x + x }

      (f << g).call(2).should == 16
      (g << f).call(2).should == 8
    end

    it "accepts any callable object" do
      inc = proc { |n| n + 1 }

      double = Object.new
      def double.call(n); n * 2; end

      (inc << double).call(3).should == 7
    end

    it_behaves_like :proc_compose, :<<, -> { proc { |s| s.upcase } }

    describe "composition" do
      it "is a Proc" do
        f = proc { |x| x * x }
        g = proc { |x| x + x }

        (f << g).is_a?(Proc).should == true
        (f << g).lambda?.should == false
      end

      it "may accept multiple arguments" do
        inc = proc { |n| n + 1 }
        mul = proc { |n, m| n * m }

        (inc << mul).call(2, 3).should == 7
      end

      it "passes blocks to the second proc" do
        ScratchPad.record []
        one = proc { |&arg| arg.call :one if arg }
        two = proc { |&arg| arg.call :two if arg }
        (one << two).call { |x| ScratchPad << x }
        ScratchPad.recorded.should == [:two]
      end
    end
  end

  describe "Proc#>>" do
    it "returns a Proc that is the composition of self and the passed Proc" do
      upcase = proc { |s| s.upcase }
      succ = proc { |s| s.succ }

      (succ >> upcase).call('Ruby').should == "RUBZ"
    end

    it "calls passed Proc with arguments and then calls self with result" do
      f = proc { |x| x * x }
      g = proc { |x| x + x }

      (f >> g).call(2).should == 8
      (g >> f).call(2).should == 16
    end

    it "accepts any callable object" do
      inc = proc { |n| n + 1 }

      double = Object.new
      def double.call(n); n * 2; end

      (inc >> double).call(3).should == 8
    end

    it_behaves_like :proc_compose, :>>, -> { proc { |s| s.upcase } }

    describe "composition" do
      it "is a Proc" do
        f = proc { |x| x * x }
        g = proc { |x| x + x }

        (f >> g).is_a?(Proc).should == true
        (f >> g).lambda?.should == false
      end

      it "may accept multiple arguments" do
        inc = proc { |n| n + 1 }
        mul = proc { |n, m| n * m }

        (mul >> inc).call(2, 3).should == 7
      end

      it "passes blocks to the first proc" do
        ScratchPad.record []
        one = proc { |&arg| arg.call :one if arg }
        two = proc { |&arg| arg.call :two if arg }
        (one >> two).call { |x| ScratchPad << x }
        ScratchPad.recorded.should == [:one]
      end
    end
  end
end
