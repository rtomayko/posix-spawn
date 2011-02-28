require 'test/unit'
require 'fastspawn'

class FastSpawnTest < Test::Unit::TestCase
  include FastSpawn

  def test_fastspawn_methods_exposed_at_module_level
    assert FastSpawn.respond_to?(:vspawn)
  end

  def test_vspawn_simple
    pid = vspawn('true')
    assert pid > 0

    chpid, status = Process.wait2
    assert_equal chpid, pid
    assert_equal 0, status.exitstatus
  end

  def test_vspawn_with_argv
    pid = vspawn('true', 'with', 'some arguments')
    assert_process_exit_ok pid
  end

  def test_fspawn
    pid = fspawn('true', 'with', 'some stuff')
    assert_process_exit_ok pid
  end

  def test_pspawn
    pid = pspawn('true', 'with', 'some stuff')
    assert_process_exit_ok pid
  end

  ##
  # Environ

  def test_pspawn_inherit_env
    ENV['PSPAWN'] = 'parent'
    pid = pspawn('/bin/sh', '-c', 'test "$PSPAWN" = "parent"')
    assert_process_exit_ok pid
  ensure
    ENV.delete('PSPAWN')
  end

  def test_pspawn_set_env
    ENV['PSPAWN'] = 'parent'
    pid = pspawn({'PSPAWN'=>'child'}, '/bin/sh', '-c', 'test "$PSPAWN" = "child"')
    assert_process_exit_ok pid
  ensure
    ENV.delete('PSPAWN')
  end

  def test_pspawn_unset_env
    ENV['PSPAWN'] = 'parent'
    pid = pspawn({'PSPAWN'=>nil}, '/bin/sh', '-c', 'test -z "$PSPAWN"')
    assert_process_exit_ok pid
  ensure
    ENV.delete('PSPAWN')
  end

  ##
  # FD => :close options

  def test_pspawn_close_option_with_symbolic_standard_stream_names
    pid = pspawn('/bin/sh', '-c', 'exec 2>/dev/null 100<&0 || true',
                 :in => :close)
    assert_process_exit_ok pid

    pid = pspawn('/bin/sh', '-c', 'exec 2>/dev/null 101>&1 102>&2 || true',
                 :out => :close, :err => :close)
    assert_process_exit_ok pid
  end

  def test_pspawn_close_option_with_fd_number
    rd, wr = IO.pipe
    pid = pspawn('/bin/sh', '-c', "exec 2>/dev/null 100<&#{rd.to_i} || true",
                 rd.to_i => :close)
    assert_process_exit_ok pid

    assert !rd.closed?
    assert !wr.closed?
  ensure
    [rd, wr].each { |fd| fd.close rescue nil }
  end

  def test_pspawn_close_option_with_io_object
    rd, wr = IO.pipe
    pid = pspawn('/bin/sh', '-c', "exec 2>/dev/null 100<&#{rd.to_i} || true",
                 rd => :close)
    assert_process_exit_ok pid

    assert !rd.closed?
    assert !wr.closed?
  ensure
    [rd, wr].each { |fd| fd.close rescue nil }
  end

  def test_pspawn_close_invalid_fd_raises_exception
    assert_raise Errno::EBADF do
      pspawn("echo", "hiya", 250 => :close)
    end
  end

  ##
  # FD => FD options

  def test_pspawn_redirect_fds_with_symbolic_names_and_io_objects
    rd, wr = IO.pipe
    pid = pspawn("echo", "hello world", :out => wr, rd => :close)
    wr.close
    output = rd.read
    assert_equal "hello world\n", output
    assert_process_exit_ok pid
  ensure
    [rd, wr].each { |fd| fd.close rescue nil }
  end

  def test_pspawn_redirect_fds_with_fd_numbers
    rd, wr = IO.pipe
    pid = pspawn("echo", "hello world", 1 => wr.fileno, rd.fileno => :close)
    wr.close
    output = rd.read
    assert_equal "hello world\n", output
    assert_process_exit_ok pid
  ensure
    [rd, wr].each { |fd| fd.close rescue nil }
  end

  def test_pspawn_redirect_invalid_fds_raises_exception
    assert_raise Errno::EBADF do
      pspawn("echo", "hiya", 250 => 3)
    end
  end

  def test_pspawn_closing_multiple_fds_with_array_keys
    rd, wr = IO.pipe
    pid = pspawn('/bin/sh', '-c', "exec 2>/dev/null 101>&#{wr.to_i} || exit 1",
                 [rd, wr, :out] => :close)
    assert_process_exit_status pid, 1
  ensure
    [rd, wr].each { |fd| fd.close rescue nil }
  end

  ##
  # Options Preprocessing

  def test_extract_process_spawn_arguments_with_options
    assert_equal [{}, ['echo', 'hello', 'world'], {:err => :close}],
      extract_process_spawn_arguments('echo', 'hello', 'world', :err => :close)
    assert_equal [{}, ['echo', 'hello', 'world'], {:err => :close}],
      extract_process_spawn_arguments(['echo', 'hello', 'world'], :err => :close)
  end

  def test_extract_process_spawn_arguments_with_options_and_env
    options = {:err => :close}
    env = {'X' => 'Y'}
    assert_equal [env, ['echo', 'hello world'], options],
      extract_process_spawn_arguments(env, 'echo', 'hello world', options)
    assert_equal [env, ['echo', 'hello world'], options],
      extract_process_spawn_arguments(env, ['echo', 'hello world'], options)
  end

  ##
  # Assertion Helpers

  def assert_process_exit_ok(pid)
    assert_process_exit_status pid, 0
  end

  def assert_process_exit_status(pid, status)
    assert pid.to_i > 0, "pid [#{pid}] should be > 0"
    chpid = Process.wait(pid)
    assert_equal chpid, pid
    assert_equal status, $?.exitstatus
  end
end
