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

![](https://chart.googleapis.com/chart?chxl=0:|50%20MB|100%20MB|150%20MB|200%20MB|250%20MB|300%20MB|350%20MB|400%20MB|450%20MB|500%20MB&cht=bvg&chdl=fspawn%20%28fork%2Bexec%29|pspawn%20%28posix_spawn%29&chtt=posix-spawn-benchmark%20-g%20-n%20500%20-m%20500%20%28i686-darwin10.5.0%29&chco=ff0000,00ff00&chf=bg,s,f8f8f8&chxt=x,y&chbh=a,5,25&chxr=1,0,3,0&chd=t:1.95,2.07,2.56,2.29,2.21,2.32,2.15,2.25,1.96,2.02|0.84,0.97,0.89,0.82,1.13,0.89,0.93,0.81,0.83,0.81&chxs=1N**%20secs&chs=900x200&chds=0,3#.png)

![](https://chart.googleapis.com/chart?chbh=a,5,25&chxr=1,0,36,7&chd=t:5.77,10.37,15.72,18.31,19.73,25.13,26.70,29.31,31.44,35.49|0.86,0.82,1.06,0.99,0.79,1.06,0.84,0.79,0.93,0.94&chxs=1N**%20secs&chs=900x200&chds=0,36&chxl=0:|50%20MB|100%20MB|150%20MB|200%20MB|250%20MB|300%20MB|350%20MB|400%20MB|450%20MB|500%20MB&cht=bvg&chdl=fspawn%20%28fork%2Bexec%29|pspawn%20%28posix_spawn%29&chtt=posix-spawn-benchmark%20-g%20-n%20500%20-m%20500%20%28x86_64-linux%29&chco=ff0000,00ff00&chf=bg,s,f8f8f8&chxt=x,y#.png)

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
