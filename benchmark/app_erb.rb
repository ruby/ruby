#
# Create many HTML strings with ERB.
#

require 'erb'

data = <<erb
<html>
  <head> <%= title %> </head>
  <body>
    <h1> <%= title %> </h1>
    <p>
      <%= content %>
    </p>
  </body>
</html>
erb

max = 15_000
title = "hello world!"
content = "hello world!\n" * 10

max.times{
  ERB.new(data).result(binding)
}
