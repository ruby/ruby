#!/usr/bin/env ruby


require 'bundler'
Bundler.require

require 'reline'
require 'optparse'
require_relative 'termination_checker'

opt = OptionParser.new
opt.on('--prompt-list-cache-timeout VAL') { |v|
  Reline::LineEditor.__send__(:remove_const, :PROMPT_LIST_CACHE_TIMEOUT)
  Reline::LineEditor::PROMPT_LIST_CACHE_TIMEOUT = v.to_f
}
opt.on('--dynamic-prompt') {
  Reline.prompt_proc = proc { |lines|
    lines.each_with_index.map { |l, i|
      '[%04d]> ' % i
    }
  }
}
opt.on('--broken-dynamic-prompt') {
  Reline.prompt_proc = proc { |lines|
    range = lines.size > 1 ? (0..(lines.size - 2)) : (0..0)
    lines[range].each_with_index.map { |l, i|
      '[%04d]> ' % i
    }
  }
}
opt.on('--dynamic-prompt-returns-empty') {
  Reline.prompt_proc = proc { |l| [] }
}
opt.on('--dynamic-prompt-with-newline') {
  Reline.prompt_proc = proc { |lines|
    range = lines.size > 1 ? (0..(lines.size - 2)) : (0..0)
    lines[range].each_with_index.map { |l, i|
      '[%04d\n]> ' % i
    }
  }
}
opt.on('--auto-indent') {
  AutoIndent.new
}
opt.on('--dialog VAL') { |v|
  Reline.add_dialog_proc(:simple_dialog, lambda {
    return nil if v.include?('nil')
    if v.include?('simple')
      contents = <<~RUBY.split("\n")
        Ruby is...
        A dynamic, open source programming
        language with a focus on simplicity
        and productivity. It has an elegant
        syntax that is natural to read and
        easy to write.
      RUBY
    elsif v.include?('long')
      contents = <<~RUBY.split("\n")
        Ruby is...
        A dynamic, open
        source programming
        language with a
        focus on simplicity
        and productivity.
        It has an elegant
        syntax that is
        natural to read
        and easy to write.
      RUBY
    elsif v.include?('fullwidth')
      contents = <<~RUBY.split("\n")
        Rubyとは...

        オープンソースの動的なプログラミン
        グ言語で、シンプルさと高い生産性を
        備えています。エレガントな文法を持
        ち、自然に読み書きができます。
      RUBY
    end
    if v.include?('scrollkey')
      dialog.trap_key = nil
      if key and key.match?(dialog.name)
        if dialog.pointer.nil?
          dialog.pointer = 0
        elsif dialog.pointer >= (contents.size - 1)
          dialog.pointer = 0
        else
          dialog.pointer += 1
        end
      end
      dialog.trap_key = [?j.ord]
      height = 4
    end
    scrollbar = false
    if v.include?('scrollbar')
      scrollbar = true
    end
    if v.include?('alt-scrollbar')
      scrollbar = true
    end
    Reline::DialogRenderInfo.new(pos: cursor_pos, contents: contents, height: height, scrollbar: scrollbar)
  })
  if v.include?('alt-scrollbar')
    ENV['RELINE_ALT_SCROLLBAR'] = '1'
  end
}
opt.on('--complete') {
  Reline.completion_proc = lambda { |target, preposing = nil, postposing = nil|
    %w{String ScriptError SyntaxError Signal}.select{ |c| c.start_with?(target) }
  }
}
opt.on('--autocomplete') {
  Reline.autocompletion = true
  Reline.completion_proc = lambda { |target, preposing = nil, postposing = nil|
    %w{String Struct Symbol ScriptError SyntaxError Signal}.select{ |c| c.start_with?(target) }
  }
}
opt.on('--autocomplete-long') {
  Reline.autocompletion = true
  Reline.completion_proc = lambda { |target, preposing = nil, postposing = nil|
    %w{
      String
      Struct
      Symbol
      StopIteration
      SystemCallError
      SystemExit
      SystemStackError
      ScriptError
      SyntaxError
      Signal
      SizedQueue
      Set
      SecureRandom
      Socket
      StringIO
      StringScanner
      Shellwords
      Syslog
      Singleton
      SDBM
    }.select{ |c| c.start_with?(target) }
  }
}
opt.on('--autocomplete-super-long') {
  Reline.autocompletion = true
  Reline.completion_proc = lambda { |target, preposing = nil, postposing = nil|
    c = 'A'
    2000.times.map{ s = "Str_#{c}"; c.succ!; s }.select{ |c| c.start_with?(target) }
  }
}

opt.on('--autocomplete-width-long') {
  Reline.autocompletion = true
  Reline.completion_proc = lambda { |target, preposing = nil, postposing = nil|
    %w{
        remove_instance_variable
        respond_to?
        ruby2_keywords
        rand
        readline
        readlines
        require
        require_relative
        raise
        respond_to_missing?
        redo
        rescue
        retry
        return
    }.select{ |c| c.start_with?(target) }
  }
}
opt.parse!(ARGV)

begin
  stty_save = `stty -g`.chomp
rescue
end

begin
  prompt = ENV['RELINE_TEST_PROMPT'] || 'prompt> '
  puts 'Multiline REPL.'
  checker = TerminationChecker.new
  while code = Reline.readmultiline(prompt, true) { |code| checker.terminated?(code) }
    case code.chomp
    when 'exit', 'quit', 'q'
      exit 0
    when ''
      # NOOP
    else
      begin
        result = eval(code)
        puts "=> #{result.inspect}"
      rescue ScriptError, StandardError => e
        puts "Traceback (most recent call last):"
        e.backtrace.reverse_each do |f|
          puts "        #{f}"
        end
        puts e.message
      end
    end
  end
rescue Interrupt
  puts '^C'
  `stty #{stty_save}` if stty_save
  exit 0
ensure
  `stty #{stty_save}` if stty_save
end
begin
  puts
rescue Errno::EIO
  # Maybe the I/O has been closed.
end
