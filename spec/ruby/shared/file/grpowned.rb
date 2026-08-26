require_relative '../../core/process/fixtures/common'

describe :file_grpowned, shared: true do
  before :each do
    @file = tmp('i_exist')
    touch(@file) { |f| f.puts "file_content" }
    File.chown(nil, Process.gid, @file) rescue nil
  end

  after :each do
    rm_r @file
  end

  platform_is_not :windows do
    it "returns true if the file exist" do
      @object.send(@method, @file).should == true
    end

    it "accepts an object that has a #to_path method" do
      @object.send(@method, mock_to_path(@file)).should == true
    end

    platform_is :darwin do
      it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
        utf8_path = tmp("file_predicate_utf8_path_\u{3042}.txt")
        # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
        non_utf8_path = utf8_path.encode(Encoding::Windows_31J)

        begin
          touch(utf8_path)
          File.chown(nil, Process.gid, utf8_path) rescue nil
          @object.send(@method, non_utf8_path).should == true
        ensure
          rm_r utf8_path
          rm_r non_utf8_path
        end
      end
    end

    it 'takes non primary groups into account' do
      skip "Codex sandbox returns EINVAL instead of EPERM for uid/gid permission changes" if ProcessSpecs.codex_sandbox?
      group = (Process.groups - [Process.egid]).first

      if group
        File.chown(nil, group, @file)

        @object.send(@method, @file).should == true
      else
        skip "No supplementary groups"
      end
    end
  end

  platform_is :windows do
    it "returns false if the file exist" do
      @object.send(@method, @file).should == false
    end
  end
end
