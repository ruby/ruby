module Rake

  # Makefile loader to be used with the import file loader.
  class MakefileLoader
    SPACE_MARK = "\0"

    # Load the makefile dependencies in +fn+.
    def load(fn)
      lines = open(fn) {|mf| mf.read}
      lines.gsub!(/\\ /, SPACE_MARK)
      lines.gsub!(/#[^\n]*\n/m, "")
      lines.gsub!(/\\\n/, ' ')
      lines.each_line do |line|
        process_line(line)
      end
    end

    private

    # Process one logical line of makefile data.
    def process_line(line)
      file_tasks, args = line.split(':', 2)
      return if args.nil?
      dependents = args.split.map {|arg| respace(arg)}
      file_tasks.scan(/\S+/) do |file_task|
        file_task = respace(file_task)
        file file_task => dependents
      end
    end

    def respace(str)
      str.tr(SPACE_MARK, ' ')
    end
  end

  # Install the handler
  Rake.application.add_loader('mf', MakefileLoader.new)
end
