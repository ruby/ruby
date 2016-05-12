# frozen_string_literal: false
begin
  require 'io/console/size'
rescue LoadError
end

##
# Stats printer that prints just the files being documented with a progress
# bar

class RDoc::Stats::Normal < RDoc::Stats::Quiet

  def begin_adding # :nodoc:
    puts "Parsing sources..."
    @last_width = 0
  end

  ##
  # Prints a file with a progress bar

  def print_file files_so_far, filename
    progress_bar = sprintf("%3d%% [%2d/%2d]  ",
                           100 * files_so_far / @num_files,
                           files_so_far,
                           @num_files)

    # Print a progress bar, but make sure it fits on a single line. Filename
    # will be truncated if necessary.
    terminal_width = if defined?(IO) && IO.respond_to?(:console_size)
                       IO.console_size[1].to_i.nonzero? || 80
                     else
                       80
                     end
    max_filename_size = terminal_width - progress_bar.size

    if filename.size > max_filename_size then
      # Turn "some_long_filename.rb" to "...ong_filename.rb"
      filename = filename[(filename.size - max_filename_size) .. -1]
      filename[0..2] = "..."
    end

    line = "#{progress_bar}#{filename}"
    if $stdout.tty?
      # Clean the line with whitespaces so that leftover output from the
      # previous line doesn't show up.
      $stdout.print("\r" << (" " * @last_width) << ("\b" * @last_width) << "\r") if @last_width && @last_width > 0
      @last_width = line.size
      $stdout.print("#{line}\r")
    else
      $stdout.puts(line)
    end
    $stdout.flush
  end

  def done_adding # :nodoc:
    puts
  end

end

