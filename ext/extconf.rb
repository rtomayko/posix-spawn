require 'mkmf'

# warnings save lives
$CFLAGS << " -Wall "

create_makefile('posix_spawn_ext')
