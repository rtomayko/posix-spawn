require 'mkmf'

# warnings save lives
$CFLAGS << " -Wall "

if RUBY_PLATFORM =~ /(mswin|mingw|bccwin)/
  File.open('Makefile','w'){|f| f.puts "default: \ninstall: " }
else
  create_makefile('posix_spawn_ext')
end

