require 'test/unit'
require 'test/unit/collector/dir'
require 'pp'

module Test
  module Unit
    module Collector
      class TestDir < TestCase
        class FileSystem
          class Directory
            def initialize(name, fs, parent=self, &block)
              @name = name
              @fs = fs
              @parent = parent
              @contents = {'.' => self, '..' => parent}
              instance_eval(&block) if(block)
            end
            
            def file(name, contents)
              @contents[name] = contents
            end

            def dir(name, &block)
              @contents[name] = self.class.new(name, @fs, self, &block)
            end

            def entries
              @contents.keys
            end

            def directory?(name)
              return true if(name.nil? || name.empty?)
              return false unless(@contents.include?(name))
              @contents[name].kind_of?(self.class)
            end

            def file?(name)
              return false unless(@contents.include?(name))
              !directory?(name)
            end

            def exist?(name)
              @contents.include?(name)
            end

            def [](name)
              raise Errno::ENOENT, name unless(@contents.include?(name))
              @contents[name]
            end

            def path_to(name=nil)
              if(!name)
                @parent.path_to(@name)
              elsif(@parent == self)
                @fs.join('/', name)
              else
                @fs.join(@parent.path_to(@name), name)
              end
            end
          end

          class ObjectSpace
            def initialize
              @objects = []
            end

            def each_object(klass, &block)
              @objects.find_all{|o| o.kind_of?(klass)}.each(&block)
            end

            def <<(object)
              @objects << object
            end
          end

          attr_reader :object_space
          
          def initialize(&block)
            @root = Directory.new('/', self, &block)
            @pwd = @root
            @object_space = ObjectSpace.new
            @required = []
          end

          def entries(dir)
            e = find(dir)
            require_directory(dir)
            e.entries
          end

          def directory?(name)
            e = find(dirname(name))
            return false unless(e)
            e.directory?(basename(name))
          end

          def find(path)
            if(/\A\// =~ path)
              path = path.sub(/\A\//, '')
              thing = @root
            else
              thing = @pwd
            end
            split(path).each do |e|
              break thing = false unless(thing.kind_of?(Directory))
              thing = thing[e]
            end
            thing
          end

          def dirname(name)
            join(*split(name)[0..-2])
          end

          def basename(name)
            split(name)[-1]
          end

          def split(name)
            name.split('/')
          end

          def join(*parts)
            parts.join('/').gsub(%r{/+}, '/')
          end

          def file?(name)
            e = find(dirname(name))
            return false unless(e)
            e.file?(basename(name))
          end

          def pwd
            @pwd.path_to
          end

          def chdir(to)
            e = find(to)
            require_directory(to)
            @pwd = e
          end

          def require_directory(path)
            raise Errno::ENOTDIR, path unless(directory?(path))
          end

          def require(file)
            return false if(@required.include?(file))
            begin
              e = find(file)
            rescue Errno::ENOENT => e
              if(/\.rb\Z/ =~ file)
                raise LoadError, file
              end
              e = find(file + '.rb')
            end
            @required << file
            @object_space << e
            true
          rescue Errno::ENOENT
            raise LoadError, file
          end
        end

        def test_dir
          inner_dir = nil
          dirs = FileSystem::Directory.new('/', nil) do
            file 'a', nil
            inner_dir = dir 'b'
          end
          assert_equal(inner_dir, dirs['b'])
        end

        def test_fs
          fs = FileSystem.new do
            file 'a', nil
            dir 'b'
          end
          assert_equal(['.', '..', 'a', 'b'].sort, fs.entries('/').sort)
          assert(fs.directory?('/'))
          assert(!fs.directory?('/a'))
          assert(!fs.directory?('/bogus'))
          assert(fs.file?('/a'))
          assert(!fs.file?('/'))
          assert(!fs.file?('/bogus'))
          assert(fs.directory?('/b'))
          assert(fs.file?('a'))
          assert(fs.directory?('b'))
        end

        def test_fs_sub
          fs = FileSystem.new do
            dir 'a' do
              file 'b', nil
              dir 'c' do
                file 'd', nil
              end
            end
          end
          assert(fs.file?('/a/b'))
          assert(!fs.file?('/a/b/c/d'))
          assert(fs.file?('/a/c/d'))
        end

        def test_fs_pwd
          fs = FileSystem.new do
            file 'a', nil
            dir 'b' do
              file 'c', nil
              dir 'd' do
                file 'e', nil
              end
            end
          end
          assert_equal('/', fs.pwd)
          assert_raises(Errno::ENOENT) do
            fs.chdir('bogus')
          end
          assert_raises(Errno::ENOTDIR) do
            fs.chdir('a')
          end
          fs.chdir('b')
          assert_equal('/b', fs.pwd)
          fs.chdir('d')
          assert_equal('/b/d', fs.pwd)
          fs.chdir('..')
          assert_equal('/b', fs.pwd)
          fs.chdir('..')
          assert_equal('/', fs.pwd)
        end

        def test_fs_entries
          fs = FileSystem.new do
            file 'a', nil
            dir 'b' do
              file 'c', nil
              file 'd', nil
            end
            file 'e', nil
            dir 'f' do
              file 'g', nil
              dir 'h' do
                file 'i', nil
              end
            end
          end
          assert_equal(['.', '..', 'a', 'b', 'e', 'f'], fs.entries('/').sort)
          assert_equal(['.', '..', 'a', 'b', 'e', 'f'], fs.entries('.').sort)
          assert_equal(['.', '..', 'a', 'b', 'e', 'f'], fs.entries('b/..').sort)
          assert_equal(['.', '..', 'c', 'd'], fs.entries('b').sort)
          assert_raises(Errno::ENOENT) do
            fs.entries('z')
          end
          assert_raises(Errno::ENOTDIR) do
            fs.entries('a')
          end
          fs.chdir('f')
          assert_equal(['.', '..', 'i'], fs.entries('h').sort)
        end

        class TestClass1
        end
        class TestClass2
        end
        def test_fs_require
          fs = FileSystem.new do
            file 'test_class1.rb', TestClass1
            dir 'dir' do
              file 'test_class2.rb', TestClass2
            end
          end
          c = []
          fs.object_space.each_object(Class) do |o|
            c << o
          end
          assert_equal([], c)

          assert_raises(LoadError) do
            fs.require('bogus')
          end
          
          assert(fs.require('test_class1.rb'))
          assert(!fs.require('test_class1.rb'))
          c = []
          fs.object_space.each_object(Class) do |o|
            c << o
          end
          assert_equal([TestClass1], c)

          fs.require('dir/test_class2')
          c = []
          fs.object_space.each_object(Class) do |o|
            c << o
          end
          assert_equal([TestClass1, TestClass2], c)

          c = []
          fs.object_space.each_object(Time) do |o|
            c << o
          end
          assert_equal([], c)
        end

        def setup
          @t1 = t1 = create_test(1)
          @t2 = t2 = create_test(2)
          @t3 = t3 = create_test(3)
          @t4 = t4 = create_test(4)
          @t5 = t5 = create_test(5)
          @t6 = t6 = create_test(6)
          fs = FileSystem.new do
            file 'test_1.rb', t1
            file 'test_2.rb', t2
            dir 'd1' do
              file 'test_3.rb', t3
            end
            file 't4.rb', t4
            dir 'd2' do
              file 'test_5', t5
              file 'test_6.rb', Time
            end
            file 't6.rb', t6
          end
          fs.require('t6')
          @c = Dir.new(fs, fs, fs.object_space, fs)
        end

        def create_test(name)
          t = Class.new(TestCase)
          t.class_eval <<-EOC
            def self.name
              "T\#{#{name}}"
            end
            def test_#{name}a
            end
            def test_#{name}b
            end
          EOC
          t
        end

        def test_simple_collect
          expected = TestSuite.new('d1')
          expected << (@t3.suite)
          assert_equal(expected, @c.collect('d1'))
        end

        def test_multilevel_collect
          expected = TestSuite.new('.')
          expected << @t1.suite << @t2.suite
          expected << (TestSuite.new('d1') << @t3.suite)
          assert_equal(expected, @c.collect)
        end

        def test_collect_file
          expected = TestSuite.new('test_1.rb')
          expected << @t1.suite
          assert_equal(expected, @c.collect('test_1.rb'))
          
          expected = TestSuite.new('t4.rb')
          expected << @t4.suite
          assert_equal(expected, @c.collect('t4.rb'))
        end

        def test_nil_pattern
          expected = TestSuite.new('d2')
          expected << @t5.suite
          @c.pattern.clear
          assert_equal(expected, @c.collect('d2'))
        end

        def test_filtering
          expected = TestSuite.new('.')
          expected << @t1.suite
          @c.filter = proc{|t| t.method_name == 'test_1a' || t.method_name == 'test_1b'}
          assert_equal(expected, @c.collect)
        end

        def test_collect_multi
          expected = TestSuite.new('[d1, d2]')
          expected << (TestSuite.new('d1') << @t3.suite)
          expected << (TestSuite.new('d2') << @t5.suite)
          @c.pattern.replace([/\btest_/])
          assert_equal(expected, @c.collect('d1', 'd2'))
        end
      end
    end
  end
end
