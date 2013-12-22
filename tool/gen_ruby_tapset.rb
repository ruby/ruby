#!/usr/bin/ruby
# -*- coding: us-ascii -*-
# usage: ./ruby gen_ruby_tapset.rb --ruby-path=/path/to/ruby probes.d > output

require "optparse"

def set_argument (argname, nth)
  # remove C style type info
  argname.gsub!(/.+ (.+)/, '\1') # e.g. char *hoge -> *hoge
  argname.gsub!(/^\*/, '')       # e.g. *filename -> filename

  "#{argname} = $arg#{nth}"
end

ruby_path = "/usr/local/ruby"

opts = OptionParser.new
opts.on("--ruby-path=PATH"){|v| ruby_path = v}
opts.parse!(ARGV)

text = ARGF.read

# remove preprocessor directives
text.gsub!(/^#.*$/, '')

# remove provider name
text.gsub!(/^provider ruby \{/, "")
text.gsub!(/^\};/, "")

# probename()
text.gsub!(/probe (.+)\( *\);/) {
  probe_name = $1
  probe = <<-End
    probe #{probe_name} = process("ruby").provider("ruby").mark("#{probe_name}")
    {
    }
  End
}

# probename(arg1)
text.gsub!(/ *probe (.+)\(([^,)]+)\);/) {
  probe_name = $1
  arg1 = $2

  probe = <<-End
    probe #{probe_name} = process("ruby").provider("ruby").mark("#{probe_name}")
    {
      #{set_argument(arg1, 1)}
    }
  End
}

# probename(arg1, arg2)
text.gsub!(/ *probe (.+)\(([^,)]+),([^,)]+)\);/) {
  probe_name = $1
  arg1 = $2
  arg2 = $3

  probe = <<-End
    probe #{probe_name} = process("#{ruby_path}").provider("ruby").mark("#{probe_name}")
    {
      #{set_argument(arg1, 1)}
      #{set_argument(arg2, 2)}
    }
  End
}

# probename(arg1, arg2, arg3)
text.gsub!(/ *probe (.+)\(([^,)]+),([^,)]+),([^,)]+)\);/) {
  probe_name = $1
  arg1 = $2
  arg2 = $3
  arg3 = $4

  probe = <<-End
    probe #{probe_name} = process("#{ruby_path}").provider("ruby").mark("#{probe_name}")
    {
      #{set_argument(arg1, 1)}
      #{set_argument(arg2, 2)}
      #{set_argument(arg3, 3)}
    }
  End
}

# probename(arg1, arg2, arg3, arg4)
text.gsub!(/ *probe (.+)\(([^,)]+),([^,)]+),([^,)]+),([^,)]+)\);/) {
  probe_name = $1
  arg1 = $2
  arg2 = $3
  arg3 = $4
  arg4 = $5

  probe = <<-End
    probe #{probe_name} = process("#{ruby_path}").provider("ruby").mark("#{probe_name}")
    {
      #{set_argument(arg1, 1)}
      #{set_argument(arg2, 2)}
      #{set_argument(arg3, 3)}
      #{set_argument(arg4, 4)}
    }
  End
}

print text

