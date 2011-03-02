# posix-spawn

`fork(2)` calls slow down as the parent process uses more memory due to the need
to copy page tables. In many common uses of fork(), where it is followed by one
of the exec family of functions to spawn child processes (`Kernel#system`,
`IO::popen`, `Process::spawn`, etc.), it's possible to remove this overhead by using
the use of special process spawning interfaces (`posix_spawn()`, `vfork()`, etc.)

The posix-spawn library aims to implement a subset of the Ruby 1.9 `Process::spawn`
interface in a way that takes advantage of fast process spawning interfaces when
available and provide sane fallbacks on systems that do not.

## BENCHMARKS

![](https://chart.googleapis.com/chart?chf=bg,s,f8f8f8&chco=ff0000,00ff00&chdl=fspawn%20%28fork%2Bexec%29|pspawn%20%28posix_spawn%29&chxt=x,x,y,y&chxr=0,50,500,50|2,0,3,0&chxp=1,50|3,50&chxl=1:|MB%20RSS|3:|Seconds&chs=900x200&cht=lc&chds=0,3.75&chd=t:2.11170196533203,1.97744297981262,1.93898510932922,2.13961386680603,2.11273097991943,2.01178789138794,1.93873310089111,1.94390201568604,1.9348361492157,2.18136882781982|0.8366379737854,0.797157049179077,0.89186692237854,1.00247001647949,0.894617080688477,0.80254602432251,0.821871995925903,0.816424131393433,0.841355085372925,0.8781578540802&chtt=posix-spawn-bm%20-g%20-n%20500%20-m%20500%20%28i686-darwin10.5.0%29#png)

![](https://chart.googleapis.com/chart?chf=bg,s,f8f8f8&chco=ff0000,00ff00&chdl=fspawn%20%28fork%2Bexec%29|pspawn%20%28posix_spawn%29&chxt=x,x,y,y&chxr=0,50,500,50|2,0,44,8&chxp=1,50|3,50&chxl=1:|MB%20RSS|3:|Seconds&chs=900x200&cht=lc&chds=0,55.0&chd=t:5.8182098865509,10.6661248207092,14.2549359798431,20.0850119590759,21.2778780460358,23.3695890903473,27.6734979152679,32.4415798187256,36.5500779151917,43.9284670352936|1.04672503471375,0.923372983932495,1.02771210670471,1.12465906143188,1.01008105278015,0.882510900497437,0.898376941680908,1.01410794258118,1.18871593475342,1.00667309761047&chtt=posix-spawn-bm%20-g%20-n%20500%20-m%20500%20%28x86_64-linux%29#png)

## USAGE

...

http://www.ruby-doc.org/core-1.9/classes/Process.html#M002230

## STATUS

These Process::spawn arguments are currently supported:

  env: hash
    name => val : set the environment variable
    name => nil : unset the environment variable
  command...:
    commandline                 : command line string which is passed to a shell
    cmdname, arg1, ...          : command name and one or more arguments (no shell)
    [cmdname, argv0], arg1, ... : command name, argv[0] and zero or more arguments (no shell)
  options: hash
    redirection:
      key:
        FD              : single file descriptor in child process
        [FD, FD, ...]   : multiple file descriptor in child process
      value:
        FD                        : redirect to the file descriptor in parent process
        :close                    : close the file descriptor in child process
        string                    : redirect to file with open(string, "r" or "w")
        [string]                  : redirect to file with open(string, File::RDONLY)
        [string, open_mode]       : redirect to file with open(string, open_mode, 0644)
        [string, open_mode, perm] : redirect to file with open(string, open_mode, perm)
      FD is one of follows
        :in     : the file descriptor 0 which is the standard input
        :out    : the file descriptor 1 which is the standard output
        :err    : the file descriptor 2 which is the standard error
        integer : the file descriptor of specified the integer
        io      : the file descriptor specified as io.fileno
    current directory:
      :chdir => str

These are NOT currently supported:

  options: hash
    clearing environment variables:
      :unsetenv_others => true   : clear environment variables except specified by env
      :unsetenv_others => false  : don't clear (default)
    process group:
      :pgroup => true or 0 : make a new process group
      :pgroup => pgid      : join to specified process group
      :pgroup => nil       : don't change the process group (default)
    resource limit: resourcename is core, cpu, data, etc.  See Process.setrlimit.
      :rlimit_resourcename => limit
      :rlimit_resourcename => [cur_limit, max_limit]
    umask:
      :umask => int
    redirection:
      value:
        [:child, FD]              : redirect to the redirected file descriptor
    file descriptor inheritance: close non-redirected non-standard fds (3, 4, 5, ...) or not
      :close_others => false : inherit fds (default for system and exec)
      :close_others => true  : don't inherit (default for spawn and IO.popen)

## ACKNOWLEDGEMENTS

Copyright (C) by Ryan Tomayko <r@tomayko.com> and Aman Gupta <aman@tmm1.net>.

See the COPYING file for more information on license and redistribution.
