k1 = "Ping Pong Ping Pong Ping Pong Ping Pong Ping Pong Ping Pong Ping Pong Ping Pong Ping Pong Ping Pong";
k2 = "Pong Ping Pong Ping Pong Ping Pong Ping Pong Ping Pong Ping Pong Ping Pong Ping Pong Ping Pong Ping";
h = {k1 => 0, k2 => 0};
3000000.times{|i| k = i % 2 ? k2 : k1; h [k] = h[k] + 1}
