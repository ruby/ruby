# frozen_string_literal: true

require 'reline'

module IRB
  # The implementation of this class is borrowed from RDoc's lib/rdoc/ri/driver.rb.
  # Please do NOT use this class directly outside of IRB.
  class Pager
    PAGE_COMMANDS = [ENV['RI_PAGER'], ENV['PAGER'], 'less', 'more'].compact.uniq

    class << self
      def page_content(content, **options)
        if content_exceeds_screen_height?(content)
          page(**options) do |io|
            io.puts content
          end
        else
          $stdout.puts content
        end
      end

      def page(retain_content: false)
        if should_page? && pager = setup_pager(retain_content: retain_content)
          begin
            pid = pager.pid
            yield pager
          ensure
            pager.close
          end
        else
          yield $stdout
        end
      # When user presses Ctrl-C, IRB would raise `IRB::Abort`
      # But since Pager is implemented by running paging commands like `less` in another process with `IO.popen`,
      # the `IRB::Abort` exception only interrupts IRB's execution but doesn't affect the pager
      # So to properly terminate the pager with Ctrl-C, we need to catch `IRB::Abort` and kill the pager process
      rescue IRB::Abort
        begin
          begin
            Process.kill("TERM", pid) if pid
          rescue Errno::EINVAL
            # SIGTERM not supported (windows)
            Process.kill("KILL", pid)
          end
        rescue Errno::ESRCH
          # Pager process already terminated
        end
        nil
      rescue Errno::EPIPE
      end

      def should_page?
        IRB.conf[:USE_PAGER] && STDIN.tty? && (ENV.key?("TERM") && ENV["TERM"] != "dumb")
      end

      def page_with_preview(width, height, formatter_proc)
        overflow_callback = ->(lines) do
          modified_output = formatter_proc.call(lines.join, true)
          content, = take_first_page(width, [height - 2, 0].max) {|o| o.write modified_output }
          content = content.chomp
          content = "#{content}\e[0m" if Color.colorable?
          $stdout.puts content
          $stdout.puts 'Preparing full inspection value...'
        end
        out = PageOverflowIO.new(width, height, overflow_callback, delay: 0.1)
        yield out
        content = formatter_proc.call(out.string, out.multipage?)
        if out.multipage?
          page(retain_content: true) do |io|
            io.puts content
          end
        else
          $stdout.puts content
        end
      end

      def take_first_page(width, height)
        overflow_callback = proc do |lines|
          return lines.join, true
        end
        out = Pager::PageOverflowIO.new(width, height, overflow_callback)
        yield out
        [out.string, false]
      end

      private

      def content_exceeds_screen_height?(content)
        screen_height, screen_width = begin
          Reline.get_screen_size
        rescue Errno::EINVAL
          [24, 80]
        end

        pageable_height = screen_height - 3 # leave some space for previous and the current prompt

        return true if content.lines.size > pageable_height

        _, overflow = take_first_page(screen_width, pageable_height) {|out| out.write content }
        overflow
      end

      def setup_pager(retain_content:)
        require 'shellwords'

        PAGE_COMMANDS.each do |pager_cmd|
          cmd = Shellwords.split(pager_cmd)
          next if cmd.empty?

          if cmd.first == 'less'
            cmd << '-R' unless cmd.include?('-R')
            cmd << '-X' if retain_content && !cmd.include?('-X')
          end

          begin
            io = IO.popen(cmd, 'w')
          rescue
            next
          end

          if $? && $?.pid == io.pid && $?.exited? # pager didn't work
            next
          end

          return io
        end

        nil
      end
    end

    # Writable IO that has page overflow callback
    class PageOverflowIO
      attr_reader :string, :first_page_lines

      # Maximum size of a single cell in terminal
      # Assumed worst case: "\e[1;3;4;9;38;2;255;128;128;48;2;128;128;255mA\e[0m"
      # bold, italic, underline, crossed_out, RGB forgound, RGB background
      MAX_CHAR_PER_CELL = 50

      def initialize(width, height, overflow_callback, delay: nil)
        @lines = []
        @first_page_lines = nil
        @width = width
        @height = height
        @buffer = +''
        @overflow_callback = overflow_callback
        @col = 0
        @string = +''
        @multipage = false
        @delay_until = (Time.now + delay if delay)
      end

      def puts(text = '')
        text = text.to_s unless text.is_a?(String)
        write(text)
        write("\n") unless text.end_with?("\n")
      end

      def write(text)
        text = text.to_s unless text.is_a?(String)
        @string << text
        if @multipage
          if @delay_until && Time.now > @delay_until
            @overflow_callback.call(@first_page_lines)
            @delay_until = nil
          end
          return
        end

        overflow_size = (@width * (@height - @lines.size) + @width - @col) * MAX_CHAR_PER_CELL
        if text.size >= overflow_size
          text = text[0, overflow_size]
          overflow = true
        end
        @buffer << text
        @col += Reline::Unicode.calculate_width(text, true)
        if text.include?("\n") || @col >= @width
          @buffer.lines.each do |line|
            wrapped_lines = Reline::Unicode.split_by_width(line.chomp, @width).first.compact
            wrapped_lines.pop if wrapped_lines.last == ''
            @lines.concat(wrapped_lines)
            if line.end_with?("\n")
              if @lines.empty? || @lines.last.end_with?("\n")
                @lines << "\n"
              else
                @lines[-1] += "\n"
              end
            end
          end
          @buffer.clear
          @buffer << @lines.pop unless @lines.last.end_with?("\n")
          @col = Reline::Unicode.calculate_width(@buffer, true)
        end
        if overflow || @lines.size > @height || (@lines.size == @height && @col > 0)
          @first_page_lines = @lines.take(@height)
          if !@delay_until || Time.now > @delay_until
            @overflow_callback.call(@first_page_lines)
            @delay_until = nil
          end
          @multipage = true
        end
      end

      def multipage?
        @multipage
      end

      alias print write
      alias << write
    end
  end
end
