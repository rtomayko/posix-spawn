require 'mkmf'

dir_config('fastspawn')

# warnings save lives
$CFLAGS << " -Wall "

create_makefile('fastspawn')
