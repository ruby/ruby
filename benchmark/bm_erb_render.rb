require 'erb'

data = DATA.read
max = 1_500_000
title = "hello world!"
content = "hello world!\n" * 10

src = "def self.render(title, content); #{ERB.new(data).src}; end"
mod = Module.new
mod.instance_eval(src, "(ERB)")

max.times do
  mod.render(title, content)
end

__END__

<html>
  <head> <%= title %> </head>
  <body>
    <h1> <%= title %> </h1>
    <p>
      <%= content %>
    </p>
  </body>
</html>
