describe "Pattern matching" do
  before :each do
    ScratchPad.record []
  end

  describe "Ruby 3.1 improvements" do
    ruby_version_is "3.1" do
      it "can omit parentheses in one line pattern matching" do
        [1, 2] => a, b
        [a, b].should == [1, 2]

        {a: 1} => a:
        a.should == 1
      end

      it "supports pinning instance variables" do
        @a = /a/
        case 'abc'
        in ^@a
          true
        end.should == true
      end

      it "supports pinning class variables" do
        result = nil
        Module.new do
          result = module_eval(<<~RUBY)
            @@a = 0..10

            case 2
            in ^@@a
              true
            end
          RUBY
        end

        result.should == true
      end

      it "supports pinning global variables" do
        $a = /a/
        case 'abc'
        in ^$a
          true
        end.should == true
      end

      it "supports pinning expressions" do
        case 'abc'
        in ^(/a/)
          true
        end.should == true

        case 0
        in ^(0 + 0)
          true
        end.should == true
      end

      it "supports pinning expressions in array pattern" do
        case [3]
        in [^(1 + 2)]
          true
        end.should == true
      end

      it "supports pinning expressions in hash pattern" do
        case {name: '2.6', released_at: Time.new(2018, 12, 25)}
        in {released_at: ^(Time.new(2010)..Time.new(2020))}
          true
        end.should == true
      end
    end
  end
end
