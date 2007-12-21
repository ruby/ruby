module Test
  module Unit
    module Collector
      class Dir
        undef collect_file
        def collect_file(name, suites, already_gathered)
          # loadpath = $:.dup
          dir = File.dirname(File.expand_path(name))
          $:.unshift(dir) unless $:.first == dir
          if(@req)
            @req.require(name)
          else
            require(name)
          end
          find_test_cases(already_gathered).each{|t| add_suite(suites, t.suite)}
        ensure
          # $:.replace(loadpath)
          $:.delete_at $:.rindex(dir)
        end
      end
    end
  end
end
