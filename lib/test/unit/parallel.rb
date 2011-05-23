require 'test/unit'

module Test
  module Unit
    class Worker < Runner
      class << self
        undef autorun
      end

      alias orig_run_suite _run_suite
      undef _run_suite
      undef _run_suites
      undef run

      def increment_io(orig)
        *rest, io = 32.times.inject([orig.dup]){|ios, | ios << ios.last.dup }
        rest.each(&:close)
        io
      end

      def _run_suites(suites, type)
        suites.map do |suite|
          _run_suite(suite, type)
        end
      end

      def _run_suite(suite, type)
        r = report.dup
        orig_stdout = MiniTest::Unit.output
        i,o = IO.pipe
        MiniTest::Unit.output = o

        th = Thread.new do
          begin
            while buf = (self.verbose ? i.gets : i.read(5))
              @stdout.puts "p #{[buf].pack("m").gsub("\n","")}"
            end
          rescue IOError
          rescue Errno::EPIPE
          end
        end

        e, f, s = @errors, @failures, @skips

        begin
          result = orig_run_suite(suite, type)
        rescue Interrupt
          @need_exit = true
          result = [nil,nil]
        end

        MiniTest::Unit.output = orig_stdout

        o.close
        begin
          th.join
        rescue IOError
          raise unless ["stream closed","closed stream"].include? $!.message
        end
        i.close

        result << (report - r)
        result << [@errors-e,@failures-f,@skips-s]
        result << ($: - @old_loadpath)
        result << suite.name

        begin
          @stdout.puts "done #{[Marshal.dump(result)].pack("m").gsub("\n","")}"
        rescue Errno::EPIPE; end
        return result
      ensure
        MiniTest::Unit.output = orig_stdout
        o.close if o && !o.closed?
        i.close if i && !i.closed?
      end

      def run(args = [])
        process_args args
        @@stop_auto_run = true
        @opts = @options.dup
        @need_exit = false

        @old_loadpath = []
        begin
          @stdout = increment_io(STDOUT)
          @stdin = increment_io(STDIN)
          @stdout.sync = true
          @stdout.puts "ready"
          while buf = @stdin.gets
            case buf.chomp
            when /^loadpath (.+?)$/
              @old_loadpath = $:.dup
              $:.push(*Marshal.load($1.unpack("m")[0].force_encoding("ASCII-8BIT"))).uniq!
            when /^run (.+?) (.+?)$/
              @stdout.puts "okay"

              @options = @opts.dup
              suites = MiniTest::Unit::TestCase.test_suites

              begin
                require $1
              rescue LoadError
                @stdout.puts "after #{[Marshal.dump([$1, $!])].pack("m").gsub("\n","")}"
                @stdout.puts "ready"
                next
              end
              _run_suites MiniTest::Unit::TestCase.test_suites-suites, $2.to_sym

              if @need_exit
                begin
                  @stdout.puts "bye"
                rescue Errno::EPIPE; end
                exit
              else
                @stdout.puts "ready"
              end
            when /^quit$/
              begin
                @stdout.puts "bye"
              rescue Errno::EPIPE; end
              exit
            end
          end
        rescue Errno::EPIPE
        rescue Exception => e
          begin
            @stdout.puts "bye #{[Marshal.dump(e)].pack("m").gsub("\n","")}"
          rescue Errno::EPIPE;end
          exit
        ensure
          @stdin.close
          @stdout.close
        end
      end
    end
  end
end

Test::Unit::Worker.new.run(ARGV)
