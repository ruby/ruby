require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/glob'

describe "Dir.glob" do
  it_behaves_like :dir_glob, :glob
end

describe "Dir.glob" do
  it_behaves_like :dir_glob_recursive, :glob
end

describe "Dir.glob" do
  before :each do
    DirSpecs.create_mock_dirs

    @cwd = Dir.pwd
    Dir.chdir DirSpecs.mock_dir
  end

  after :each do
    Dir.chdir @cwd

    DirSpecs.delete_mock_dirs
  end

  it "can take an array of patterns" do
    Dir.glob(["file_o*", "file_t*"]).should ==
               %w!file_one.ext file_two.ext!
  end

  it 'returns matching file paths when supplied :base keyword argument' do
    dir = tmp('dir_glob_base')
    file_1 = "#{dir}/lib/bloop.rb"
    file_2 = "#{dir}/lib/soup.rb"
    file_3 = "#{dir}/lib/mismatched_file_type.txt"
    file_4 = "#{dir}/mismatched_directory.rb"

    touch file_1
    touch file_2
    touch file_3
    touch file_4

    Dir.glob('**/*.rb', base: "#{dir}/lib").sort.should == ["bloop.rb", "soup.rb"].sort
  ensure
    rm_r dir
  end

  it "calls #to_path to convert multiple patterns" do
    pat1 = mock('file_one.ext')
    pat1.should_receive(:to_path).and_return('file_one.ext')
    pat2 = mock('file_two.ext')
    pat2.should_receive(:to_path).and_return('file_two.ext')

    Dir.glob([pat1, pat2]).should == %w[file_one.ext file_two.ext]
  end

  it "matches both dot and non-dotfiles with '*' and option File::FNM_DOTMATCH" do
    Dir.glob('*', File::FNM_DOTMATCH).sort.should == DirSpecs.expected_glob_paths
  end

  it "matches files with any beginning with '*<non-special characters>' and option File::FNM_DOTMATCH" do
    Dir.glob('*file', File::FNM_DOTMATCH).sort.should == %w|.dotfile nondotfile|.sort
  end

  it "matches any files in the current directory with '**' and option File::FNM_DOTMATCH" do
    Dir.glob('**', File::FNM_DOTMATCH).sort.should == DirSpecs.expected_glob_paths
  end

  it "recursively matches any subdirectories except './' or '../' with '**/' from the current directory and option File::FNM_DOTMATCH" do
    expected = %w[
      .dotsubdir/
      brace/
      deeply/
      deeply/nested/
      deeply/nested/directory/
      deeply/nested/directory/structure/
      dir/
      nested/
      nested/.dotsubir/
      special/
      special/test\ +()[]{}/
      special/test{1}/
      special/{}/
      subdir_one/
      subdir_two/
    ]

    Dir.glob('**/', File::FNM_DOTMATCH).sort.should == expected
  end

  ruby_version_is ''...'3.1' do
    it "recursively matches files and directories in nested dot subdirectory with 'nested/**/*' from the current directory and option File::FNM_DOTMATCH" do
      expected = %w[
        nested/.
        nested/.dotsubir
        nested/.dotsubir/.
        nested/.dotsubir/.dotfile
        nested/.dotsubir/nondotfile
      ]

      Dir.glob('nested/**/*', File::FNM_DOTMATCH).sort.should == expected.sort
    end
  end

  ruby_version_is '3.1' do
    it "recursively matches files and directories in nested dot subdirectory except . with 'nested/**/*' from the current directory and option File::FNM_DOTMATCH" do
      expected = %w[
        nested/.
        nested/.dotsubir
        nested/.dotsubir/.dotfile
        nested/.dotsubir/nondotfile
      ]

      Dir.glob('nested/**/*', File::FNM_DOTMATCH).sort.should == expected.sort
    end
  end

  # This is a separate case to check **/ coming after a constant
  # directory as well.
  it "recursively matches any subdirectories except './' or '../' with '**/' and option File::FNM_DOTMATCH" do
    expected = %w[
      ./
      ./.dotsubdir/
      ./brace/
      ./deeply/
      ./deeply/nested/
      ./deeply/nested/directory/
      ./deeply/nested/directory/structure/
      ./dir/
      ./nested/
      ./nested/.dotsubir/
      ./special/
      ./special/test\ +()[]{}/
      ./special/test{1}/
      ./special/{}/
      ./subdir_one/
      ./subdir_two/
    ]

    Dir.glob('./**/', File::FNM_DOTMATCH).sort.should == expected
  end

  it "matches a list of paths by concatenating their individual results" do
    expected = %w[
      deeply/
      deeply/nested/
      deeply/nested/directory/
      deeply/nested/directory/structure/
      subdir_two/nondotfile
      subdir_two/nondotfile.ext
    ]

    Dir.glob('{deeply/**/,subdir_two/*}').sort.should == expected
  end

  it "preserves multiple /s before a **" do
    expected = %w[
      deeply//nested/directory/structure
    ]

    Dir.glob('{deeply//**/structure}').sort.should == expected
  end

  it "accepts a block and yields it with each elements" do
    ary = []
    ret = Dir.glob(["file_o*", "file_t*"]) { |t| ary << t }
    ret.should be_nil
    ary.should == %w!file_one.ext file_two.ext!
  end

  it "ignores non-dirs when traversing recursively" do
    touch "spec"
    Dir.glob("spec/**/*.rb").should == []
  end

  it "matches nothing when given an empty list of paths" do
    Dir.glob('{}').should == []
  end

  it "handles infinite directory wildcards" do
    Dir.glob('**/**/**').should_not.empty?
  end

  it "handles **/** with base keyword argument" do
    Dir.glob('**/**', base: "dir").should == ["filename_ordering"]

    expected = %w[
      nested
      nested/directory
      nested/directory/structure
      nested/directory/structure/bar
      nested/directory/structure/baz
      nested/directory/structure/file_one
      nested/directory/structure/file_one.ext
      nested/directory/structure/foo
      nondotfile
    ].sort

    Dir.glob('**/**', base: "deeply").sort.should == expected
  end

  it "handles **/ with base keyword argument" do
    expected = %w[
      /
      directory/
      directory/structure/
    ]
    Dir.glob('**/', base: "deeply/nested").sort.should == expected
  end

  it "handles **/nondotfile with base keyword argument" do
    expected = %w[
      deeply/nondotfile
      nondotfile
      subdir_one/nondotfile
      subdir_two/nondotfile
    ]
    Dir.glob('**/nondotfile', base: ".").sort.should == expected
  end

  it "handles **/nondotfile with base keyword argument and FNM_DOTMATCH" do
    expected = %w[
      .dotsubdir/nondotfile
      deeply/nondotfile
      nested/.dotsubir/nondotfile
      nondotfile
      subdir_one/nondotfile
      subdir_two/nondotfile
    ]
    Dir.glob('**/nondotfile', File::FNM_DOTMATCH, base: ".").sort.should == expected
  end

  it "handles **/.dotfile with base keyword argument" do
    expected = %w[
      .dotfile
      deeply/.dotfile
      subdir_one/.dotfile
    ]
    Dir.glob('**/.dotfile', base: ".").sort.should == expected
  end

  it "handles **/.dotfile with base keyword argument and FNM_DOTMATCH" do
    expected = %w[
      .dotfile
      .dotsubdir/.dotfile
      deeply/.dotfile
      nested/.dotsubir/.dotfile
      subdir_one/.dotfile
    ]
    Dir.glob('**/.dotfile', File::FNM_DOTMATCH, base: ".").sort.should == expected
  end

  it "handles **/.* with base keyword argument" do
    expected = %w[
      .dotfile.ext
      directory/structure/.ext
    ].sort

    Dir.glob('**/.*', base: "deeply/nested").sort.should == expected
  end

  # < 3.1 include a "." entry for every dir: ["directory/.", "directory/structure/.", ...]
  ruby_version_is '3.1' do
    it "handles **/.* with base keyword argument and FNM_DOTMATCH" do
      expected = %w[
        .
        .dotfile.ext
        directory/structure/.ext
      ].sort

      Dir.glob('**/.*', File::FNM_DOTMATCH, base: "deeply/nested").sort.should == expected
    end

    it "handles **/** with base keyword argument and FNM_DOTMATCH" do
      expected = %w[
        .
        .dotfile.ext
        directory
        directory/structure
        directory/structure/.ext
        directory/structure/bar
        directory/structure/baz
        directory/structure/file_one
        directory/structure/file_one.ext
        directory/structure/foo
      ].sort

      Dir.glob('**/**', File::FNM_DOTMATCH, base: "deeply/nested").sort.should == expected
    end
  end

  it "handles **/*pattern* with base keyword argument and FNM_DOTMATCH" do
    expected = %w[
      .dotfile.ext
      directory/structure/file_one
      directory/structure/file_one.ext
    ]

    Dir.glob('**/*file*', File::FNM_DOTMATCH, base: "deeply/nested").sort.should == expected
  end

  it "handles **/glob with base keyword argument and FNM_EXTGLOB" do
    expected = %w[
      directory/structure/bar
      directory/structure/file_one
      directory/structure/file_one.ext
    ]

    Dir.glob('**/*{file,bar}*', File::FNM_EXTGLOB, base: "deeply/nested").sort.should == expected
  end

  it "handles simple filename patterns" do
    Dir.glob('.dotfile').should == ['.dotfile']
  end

  it "handles simple directory patterns" do
    Dir.glob('.dotsubdir/').should == ['.dotsubdir/']
  end

  it "handles simple directory patterns applied to non-directories" do
    Dir.glob('nondotfile/').should == []
  end

  platform_is_not(:windows) do
    it "matches the literal character '\\' with option File::FNM_NOESCAPE" do
      Dir.mkdir 'foo?bar'

      begin
        Dir.glob('foo?bar', File::FNM_NOESCAPE).should == %w|foo?bar|
        Dir.glob('foo\?bar', File::FNM_NOESCAPE).should == []
      ensure
        Dir.rmdir 'foo?bar'
      end

      Dir.mkdir 'foo\?bar'

      begin
        Dir.glob('foo\?bar', File::FNM_NOESCAPE).should == %w|foo\\?bar|
      ensure
        Dir.rmdir 'foo\?bar'
      end
    end

    it "returns nil for directories current user has no permission to read" do
      Dir.mkdir('no_permission')
      File.chmod(0, 'no_permission')

      begin
        Dir.glob('no_permission/*').should == []
      ensure
        Dir.rmdir('no_permission')
      end
    end

    it "will follow symlinks when processing a `*/` pattern." do
      expected = ['special/ln/nondotfile']
      Dir.glob('special/*/nondotfile').should == expected
    end

    it "will not follow symlinks when recursively traversing directories" do
      expected = %w[
        deeply/nondotfile
        nondotfile
        subdir_one/nondotfile
        subdir_two/nondotfile
      ]
      Dir.glob('**/nondotfile').sort.should == expected
    end

    it "will follow symlinks when testing directory after recursive directory in pattern" do
      expected = %w[
        deeply/nondotfile
        special/ln/nondotfile
        subdir_one/nondotfile
        subdir_two/nondotfile
      ]
      Dir.glob('**/*/nondotfile').sort.should == expected
    end
  end
end
