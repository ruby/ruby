require 'test/unit/testsuite'
require 'test/unit/collector'

module Test
  module Unit
    module Collector
      class Dir
        include Collector

        attr_reader :pattern, :exclude

        def initialize(dir=::Dir, file=::File, object_space=::ObjectSpace, req=nil)
          super()
          @dir = dir
          @file = file
          @object_space = object_space
          @req = req
          @pattern = [/\btest_.*\.rb\Z/m]
          @exclude = []
        end

        def collect(*from)
          if(from.empty?)
            recursive_collect('.', find_test_cases)
          elsif(from.size == 1)
            recursive_collect(from.first, find_test_cases)
          else
            suites = []
            from.each do |f|
              suite = recursive_collect(f, find_test_cases)
              suites << suite unless(suite.tests.empty?)
            end
            suite = TestSuite.new("[#{from.join(', ')}]")
            sort(suites).each{|s| suite << s}
            suite
          end
        end

        def find_test_cases(ignore=[])
          cases = []
          @object_space.each_object(Class) do |c|
            cases << c if(c < TestCase && !ignore.include?(c))
          end
          ignore.concat(cases)
          cases
        end

        def recursive_collect(name, already_gathered)
          sub_suites = []
          if(@file.directory?(name))
            @dir.entries(name).each do |e|
              next if(e == '.' || e == '..')
              e_name = @file.join(name, e)
              if(@file.directory?(e_name))
                next if /\ACVS\z/ =~ e
                sub_suite = recursive_collect(e_name, already_gathered)
                sub_suites << sub_suite unless(sub_suite.empty?)
              else
                next if /~\z/ =~ e_name or /\A\.\#/ =~ e
                if @pattern and !@pattern.empty?
                  next unless @pattern.any? {|pat| pat =~ e_name}
                end
                if @exclude and !@exclude.empty?
                  next if @exclude.any? {|pat| pat =~ e_name}
                end
                collect_file(e_name, sub_suites, already_gathered)
              end
            end
          else
            collect_file(name, sub_suites, already_gathered)
          end
          suite = TestSuite.new(@file.basename(name))
          sort(sub_suites).each{|s| suite << s}
          suite
        end

        def collect_file(name, suites, already_gathered)
          loadpath = $:.dup
          dir = File.dirname(File.expand_path(name))
          $:.unshift(dir) unless $:.first == dir
          if(@req)
            @req.require(name)
          else
            require(name)
          end
          find_test_cases(already_gathered).each{|t| add_suite(suites, t.suite)}
        ensure
          $:.replace(loadpath)
        end
      end
    end
  end
end
