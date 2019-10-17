require_relative '../spec_helper'

# See core/kernel/eval_spec.rb for more magic comments specs for eval()
describe :magic_comments, shared: true do
  before :each do
    @default = @method == :locale ? Encoding.find('locale') : Encoding::UTF_8
  end

  it "are optional" do
    @object.call('no_magic_comment.rb').should == @default.name
  end

  it "are case-insensitive" do
    @object.call('case_magic_comment.rb').should == Encoding::Big5.name
  end

  it "must be at the first line" do
    @object.call('second_line_magic_comment.rb').should == @default.name
  end

  it "must be the first token of the line" do
    @object.call('second_token_magic_comment.rb').should == @default.name
  end

  it "can be after the shebang" do
    @object.call('shebang_magic_comment.rb').should == Encoding::Big5.name
  end

  it "can take Emacs style" do
    @object.call('emacs_magic_comment.rb').should == Encoding::Big5.name
  end

  it "can take vim style" do
    @object.call('vim_magic_comment.rb').should == Encoding::Big5.name
  end

  it "determine __ENCODING__" do
    @object.call('magic_comment.rb').should == Encoding::Big5.name
  end

  it "do not cause bytes to be mangled by passing them through the wrong encoding" do
    @object.call('bytes_magic_comment.rb').should == [167, 65, 166, 110].inspect
  end
end

describe "Magic comments" do
  describe "in stdin" do
    it_behaves_like :magic_comments, :locale, -> file {
      print_at_exit = fixture(__FILE__, "print_magic_comment_result_at_exit.rb")
      ruby_exe(nil, args: "< #{fixture(__FILE__, file)}", options: "-r#{print_at_exit}")
    }
  end

  platform_is_not :windows do
    describe "in an -e argument" do
      it_behaves_like :magic_comments, :locale, -> file {
        print_at_exit = fixture(__FILE__, "print_magic_comment_result_at_exit.rb")
        # Use UTF-8, as it is the default source encoding for files
        code = File.read(fixture(__FILE__, file), encoding: 'utf-8')
        IO.popen([*ruby_exe, "-r", print_at_exit, "-e", code], &:read)
      }
    end
  end

  describe "in the main file" do
    it_behaves_like :magic_comments, :UTF8, -> file {
      print_at_exit = fixture(__FILE__, "print_magic_comment_result_at_exit.rb")
      ruby_exe(fixture(__FILE__, file), options: "-r#{print_at_exit}")
    }
  end

  describe "in a loaded file" do
    it_behaves_like :magic_comments, :UTF8, -> file {
      load fixture(__FILE__, file)
      $magic_comment_result
    }
  end

  describe "in a required file" do
    it_behaves_like :magic_comments, :UTF8, -> file {
      require fixture(__FILE__, file)
      $magic_comment_result
    }
  end

  describe "in an eval" do
    it_behaves_like :magic_comments, :UTF8, -> file {
      # Use UTF-8, as it is the default source encoding for files
      eval(File.read(fixture(__FILE__, file), encoding: 'utf-8'))
    }
  end
end
