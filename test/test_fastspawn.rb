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

  # TODO these don't really test that the fds were closed so well
  def test_pspawn_close_option_with_symbolic_standard_stream_names
    pid = pspawn('cat', :in => :close)
    assert_process_exit_status pid, 1

    pid = pspawn('cat', :in => :close, :out => :close, :err => :close)
    assert_process_exit_status pid, 1
  end

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
