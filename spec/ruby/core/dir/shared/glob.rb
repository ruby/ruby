# -*- encoding: utf-8 -*-
describe :dir_glob, shared: true do
  before :all do
    DirSpecs.create_mock_dirs
    @cwd = Dir.pwd
    Dir.chdir DirSpecs.mock_dir
  end

  after :all do
    Dir.chdir @cwd
    DirSpecs.delete_mock_dirs
  end

  it "raises an Encoding::CompatibilityError if the argument encoding is not compatible with US-ASCII" do
    pattern = "file*".force_encoding Encoding::UTF_16BE
    -> { Dir.send(@method, pattern) }.should raise_error(Encoding::CompatibilityError)
  end

  it "calls #to_path to convert a pattern" do
    obj = mock('file_one.ext')
    obj.should_receive(:to_path).and_return('file_one.ext')

    Dir.send(@method, obj).should == %w[file_one.ext]
  end

  it "raises an ArgumentError if the string contains \\0" do
    -> {Dir.send(@method, "file_o*\0file_t*")}.should raise_error ArgumentError, /nul-separated/
  end

  ruby_version_is "3.0" do
    it "result is sorted by default" do
      result = Dir.send(@method, '*')
      result.should == result.sort
    end

    it "result is sorted with sort: true" do
      result = Dir.send(@method, '*', sort: true)
      result.should == result.sort
    end

    it "sort: false returns same files" do
      result = Dir.send(@method,'*', sort: false)
      result.sort.should == Dir.send(@method, '*').sort
    end
  end

  ruby_version_is "3.0"..."3.1" do
    it "result is sorted with any non false value of sort:" do
      result = Dir.send(@method, '*', sort: 0)
      result.should == result.sort

      result = Dir.send(@method, '*', sort: nil)
      result.should == result.sort

      result = Dir.send(@method, '*', sort: 'false')
      result.should == result.sort
    end
  end

  ruby_version_is "3.1" do
    it "raises an ArgumentError if sort: is not true or false" do
      -> { Dir.send(@method, '*', sort: 0) }.should raise_error ArgumentError, /expected true or false/
      -> { Dir.send(@method, '*', sort: nil) }.should raise_error ArgumentError, /expected true or false/
      -> { Dir.send(@method, '*', sort: 'false') }.should raise_error ArgumentError, /expected true or false/
    end
  end

  it "matches non-dotfiles with '*'" do
    expected = %w[
      brace
      deeply
      dir
      dir_filename_ordering
      file_one.ext
      file_two.ext
      nested
      nondotfile
      special
      subdir_one
      subdir_two
    ]

    Dir.send(@method,'*').sort.should == expected
  end

  it "returns empty array when empty pattern provided" do
    Dir.send(@method, '').should == []
  end

  it "matches regexp special +" do
    Dir.send(@method, 'special/+').should == ['special/+']
  end

  it "matches directories with special characters when escaped" do
    Dir.send(@method, 'special/\{}/special').should == ["special/{}/special"]
  end

  platform_is_not :windows do
    it "matches regexp special *" do
      Dir.send(@method, 'special/\*').should == ['special/*']
    end

    it "matches regexp special ?" do
      Dir.send(@method, 'special/\?').should == ['special/?']
    end

    it "matches regexp special |" do
      Dir.send(@method, 'special/|').should == ['special/|']
    end

    it "matches files with backslashes in their name" do
      Dir.glob('special/\\\\{a,b}').should == ['special/\a']
    end
  end

  it "matches regexp special ^" do
    Dir.send(@method, 'special/^').should == ['special/^']
  end

  it "matches regexp special $" do
    Dir.send(@method, 'special/$').should == ['special/$']
  end

  it "matches regexp special (" do
    Dir.send(@method, 'special/(').should == ['special/(']
  end

  it "matches regexp special )" do
    Dir.send(@method, 'special/)').should == ['special/)']
  end

  it "matches regexp special [" do
    Dir.send(@method, 'special/\[').should == ['special/[']
  end

  it "matches regexp special ]" do
    Dir.send(@method, 'special/]').should == ['special/]']
  end

  it "matches regexp special {" do
    Dir.send(@method, 'special/\{').should == ['special/{']
  end

  it "matches regexp special }" do
    Dir.send(@method, 'special/\}').should == ['special/}']
  end

  it "matches paths with glob patterns" do
    Dir.send(@method, 'special/test\{1\}/*').should == ['special/test{1}/file[1]']
  end

  ruby_version_is ''...'3.1' do
    it "matches dotfiles with '.*'" do
      Dir.send(@method, '.*').sort.should == %w|. .. .dotfile .dotsubdir|.sort
    end
  end

  ruby_version_is '3.1' do
    it "matches dotfiles except .. with '.*'" do
      Dir.send(@method, '.*').sort.should == %w|. .dotfile .dotsubdir|.sort
    end
  end

  it "matches non-dotfiles with '*<non-special characters>'" do
    Dir.send(@method, '*file').sort.should == %w|nondotfile|.sort
  end

  it "matches dotfiles with '.*<non-special characters>'" do
    Dir.send(@method, '.*file').sort.should == %w|.dotfile|.sort
  end

  it "matches files with any ending with '<non-special characters>*'" do
    Dir.send(@method, 'file*').sort.should == %w|file_one.ext file_two.ext|.sort
  end

  it "matches files with any middle with '<non-special characters>*<non-special characters>'" do
    Dir.send(@method, 'sub*_one').sort.should == %w|subdir_one|.sort
  end

  it "handles directories with globs" do
    Dir.send(@method, 'sub*/*').sort.should == %w!subdir_one/nondotfile subdir_two/nondotfile subdir_two/nondotfile.ext!
  end

  it "matches files with multiple '*' special characters" do
    Dir.send(@method, '*fi*e*').sort.should == %w|dir_filename_ordering nondotfile file_one.ext file_two.ext|.sort
  end

  it "matches non-dotfiles in the current directory with '**'" do
    expected = %w[
      brace
      deeply
      dir
      dir_filename_ordering
      file_one.ext
      file_two.ext
      nested
      nondotfile
      special
      subdir_one
      subdir_two
    ]

    Dir.send(@method, '**').sort.should == expected
  end

  ruby_version_is ''...'3.1' do
    it "matches dotfiles in the current directory with '.**'" do
      Dir.send(@method, '.**').sort.should == %w|. .. .dotsubdir .dotfile|.sort
    end
  end

  ruby_version_is '3.1' do
    it "matches dotfiles in the current directory except .. with '.**'" do
      Dir.send(@method, '.**').sort.should == %w|. .dotsubdir .dotfile|.sort
    end
  end

  it "recursively matches any nondot subdirectories with '**/'" do
    expected = %w[
      brace/
      deeply/
      deeply/nested/
      deeply/nested/directory/
      deeply/nested/directory/structure/
      dir/
      nested/
      special/
      special/test{1}/
      special/{}/
      subdir_one/
      subdir_two/
    ]

    Dir.send(@method, '**/').sort.should == expected
  end

  it "recursively matches any subdirectories except './' or '../' with '**/' from the base directory if that is specified" do
    expected = %w[
      nested/directory
    ]

    Dir.send(@method, '**/*ory', base: 'deeply').sort.should == expected
  end

  ruby_version_is ''...'3.1' do
    it "recursively matches any subdirectories including ./ and ../ with '.**/'" do
      Dir.chdir("#{DirSpecs.mock_dir}/subdir_one") do
        Dir.send(@method, '.**/').sort.should == %w|./ ../|.sort
      end
    end
  end

  ruby_version_is '3.1' do
    it "recursively matches any subdirectories including ./ with '.**/'" do
      Dir.chdir("#{DirSpecs.mock_dir}/subdir_one") do
        Dir.send(@method, '.**/').should == ['./']
      end
    end
  end

  it "matches a single character except leading '.' with '?'" do
    Dir.send(@method, '?ubdir_one').sort.should == %w|subdir_one|.sort
  end

  it "accepts multiple '?' characters in a pattern" do
    Dir.send(@method, 'subdir_???').sort.should == %w|subdir_one subdir_two|.sort
  end

  it "matches any characters in a set with '[<characters>]'" do
    Dir.send(@method, '[stfu]ubdir_one').sort.should == %w|subdir_one|.sort
  end

  it "matches any characters in a range with '[<character>-<character>]'" do
    Dir.send(@method, '[a-zA-Z]ubdir_one').sort.should == %w|subdir_one|.sort
  end

  it "matches any characters except those in a set with '[^<characters>]'" do
    Dir.send(@method, '[^wtf]ubdir_one').sort.should == %w|subdir_one|.sort
  end

  it "matches any characters except those in a range with '[^<character>-<character]'" do
    Dir.send(@method, '[^0-9]ubdir_one').sort.should == %w|subdir_one|.sort
  end

  it "matches any one of the strings in a set with '{<string>,<other>,...}'" do
    Dir.send(@method, 'subdir_{one,two,three}').sort.should == %w|subdir_one subdir_two|.sort
  end

  it "matches a set '{<string>,<other>,...}' which also uses a glob" do
    Dir.send(@method, 'sub*_{one,two,three}').sort.should == %w|subdir_one subdir_two|.sort
  end

  it "accepts string sets with empty strings with {<string>,,<other>}" do
    a = Dir.send(@method, 'deeply/nested/directory/structure/file_one{.ext,}').sort
    a.should == %w|deeply/nested/directory/structure/file_one.ext
                   deeply/nested/directory/structure/file_one|.sort
  end

  it "matches dot or non-dotfiles with '{,.}*'" do
    Dir.send(@method, '{,.}*').sort.should == DirSpecs.expected_glob_paths
  end

  it "respects the order of {} expressions, expanding left most first" do
    files = Dir.send(@method, "brace/a{.js,.html}{.erb,.rjs}")
    files.should == %w!brace/a.js.rjs brace/a.html.erb!
  end

  it "respects the optional nested {} expressions" do
    files = Dir.send(@method, "brace/a{.{js,html},}{.{erb,rjs},}")
    files.should == %w!brace/a.js.rjs brace/a.js brace/a.html.erb brace/a.erb brace/a!
  end

  it "matches special characters by escaping with a backslash with '\\<character>'" do
    Dir.mkdir 'foo^bar'

    begin
      Dir.send(@method, 'foo?bar').should == %w|foo^bar|
      Dir.send(@method, 'foo\?bar').should == []
      Dir.send(@method, 'nond\otfile').should == %w|nondotfile|
    ensure
      Dir.rmdir 'foo^bar'
    end
  end

  it "recursively matches directories with '**/<characters>'" do
    Dir.send(@method, '**/*fil?{,.}*').uniq.sort.should ==
      %w[deeply/nested/directory/structure/file_one
         deeply/nested/directory/structure/file_one.ext
         deeply/nondotfile

         dir/filename_ordering
         dir_filename_ordering

         file_one.ext
         file_two.ext

         nondotfile

         special/test{1}/file[1]

         subdir_one/nondotfile
         subdir_two/nondotfile
         subdir_two/nondotfile.ext]
  end

  it "ignores matching through directories that doesn't exist" do
    Dir.send(@method, "deeply/notthere/blah*/whatever").should == []
  end

  it "ignores matching only directories under an nonexistent path" do
    Dir.send(@method, "deeply/notthere/blah/").should == []
  end

  platform_is_not :windows do
    it "matches UTF-8 paths" do
      Dir.send(@method, "special/こんにちは{,.txt}").should == ["special/こんにちは.txt"]
    end
  end

  context ":base option passed" do
    before :each do
      @mock_dir = File.expand_path tmp('dir_glob_mock')

      %w[
        a/b/x
        a/b/c/y
        a/b/c/d/z
      ].each do |path|
        file = File.join @mock_dir, path
        mkdir_p File.dirname(file)
        touch file
      end
    end

    after :each do
      rm_r @mock_dir
    end

    it "matches entries only from within the specified directory" do
      path = File.join(@mock_dir, "a/b/c")
      Dir.send(@method, "*", base: path).sort.should == %w( d y )
    end

    it "accepts both relative and absolute paths" do
      require 'pathname'

      path_abs = File.join(@mock_dir, "a/b/c")
      path_rel = Pathname.new(path_abs).relative_path_from(Pathname.new(Dir.pwd))

      result_abs = Dir.send(@method, "*", base: path_abs).sort
      result_rel = Dir.send(@method, "*", base: path_rel).sort

      result_abs.should == %w( d y )
      result_rel.should == %w( d y )
    end

    it "returns [] if specified path does not exist" do
      path = File.join(@mock_dir, "fake-name")
      File.should_not.exist?(path)

      Dir.send(@method, "*", base: path).should == []
    end

    it "returns [] if specified path is a file" do
      path = File.join(@mock_dir, "a/b/x")
      File.should.exist?(path)

      Dir.send(@method, "*", base: path).should == []
    end

    it "raises TypeError when cannot convert value to string" do
      -> {
        Dir.send(@method, "*", base: [])
      }.should raise_error(TypeError)
    end

    it "handles '' as current directory path" do
      Dir.chdir @mock_dir do
        Dir.send(@method, "*", base: "").should == %w( a )
      end
    end

    it "handles nil as current directory path" do
      Dir.chdir @mock_dir do
        Dir.send(@method, "*", base: nil).should == %w( a )
      end
    end
  end
end

describe :dir_glob_recursive, shared: true do
  before :each do
    @cwd = Dir.pwd
    @mock_dir = File.expand_path tmp('dir_glob_mock')

    %w[
      a/x/b/y/e
      a/x/b/y/b/z/e
    ].each do |path|
      file = File.join @mock_dir, path
      mkdir_p File.dirname(file)
      touch file
    end

    Dir.chdir @mock_dir
  end

  after :each do
    Dir.chdir @cwd
    rm_r @mock_dir
  end

  it "matches multiple recursives" do
    expected = %w[
      a/x/b/y/b/z/e
      a/x/b/y/e
    ]

    Dir.send(@method, 'a/**/b/**/e').uniq.sort.should == expected
  end

  platform_is_not :windows do
    it "ignores symlinks" do
      file = File.join @mock_dir, 'b/z/e'
      link = File.join @mock_dir, 'a/y'

      mkdir_p File.dirname(file)
      touch file
      File.symlink(File.dirname(file), link)

      expected = %w[
        a/x/b/y/b/z/e
        a/x/b/y/e
      ]

      Dir.send(@method, 'a/**/e').uniq.sort.should == expected
    end
  end
end
