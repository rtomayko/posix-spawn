/* we want GNU extensions like POSIX_SPAWN_USEVFORK */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <unistd.h>
#include <ruby.h>
#include <st.h>

#ifndef RARRAY_LEN
#define RARRAY_LEN(ary) RARRAY(ary)->len
#endif
#ifndef RARRAY_PTR
#define RARRAY_PTR(ary) RARRAY(ary)->ptr
#endif

extern char **environ;

static VALUE rb_mFastSpawn;

static VALUE
rb_fastspawn_vspawn(VALUE self, VALUE env, VALUE argv, VALUE options)
{
	int i;
	int argc = RARRAY_LEN(argv);
	char *cargv[argc + 1];
	pid_t pid;

	cargv[argc] = NULL;
	for(i = 0; i < argc; i++)
		cargv[i] = StringValuePtr(RARRAY_PTR(argv)[i]);

	pid = vfork();
	if(pid < 0) {
		rb_sys_fail("vfork");
	}
	if(!pid) {
		execvp(cargv[0], cargv);
		_exit(1);
	}

	return INT2FIX(pid);
}

/* Hash iterator that sets up the posix_spawn_file_actions_t with addclose
 * instructions. Only hash pairs whose value is :close are processed. Keys may
 * be the :in, :out, :err, an IO object, or a Fixnum fd number.
 *
 * Returns ST_DELETE when an addclose instruction was added; ST_CONTINUE when
 * no operation was performed.
 */
static int
fastspawn_file_actions_addclose_iter(VALUE key, VALUE val, posix_spawn_file_actions_t *fops)
{
	int fd;

	/* we only care about { (IO|FD|:in|:out|:err) => :close } */
	if (SYM2ID(val) != rb_intern("close"))
		return ST_CONTINUE;

	fd  = -1;
	switch (TYPE(key)) {
		case T_FIXNUM:
			/* FD => :close */
			fd = FIX2INT(key);
			break;

		case T_SYMBOL:
			/* (:in|:out|:err) => :close */
			if      (SYM2ID(key) == rb_intern("in"))   fd = 0;
			else if (SYM2ID(key) == rb_intern("out"))  fd = 1;
			else if (SYM2ID(key) == rb_intern("err"))  fd = 2;
			break;

		case T_OBJECT:
			/* IO => :close */
			if (rb_respond_to(key, rb_intern("to_io"))) {
				key = rb_funcall(key, rb_intern("to_io"), 0);
				fd = FIX2INT(rb_funcall(key, rb_intern("fileno"), 0));
			}
			break;

		default:
			break;
	}

	if (fd >= 0) {
		posix_spawn_file_actions_addclose(fops, fd);
		return ST_DELETE;
	} else {
		return ST_CONTINUE;
	}
}

static void
fastspawn_file_actions_addclose(posix_spawn_file_actions_t *fops, VALUE options)
{
	rb_hash_foreach(options, fastspawn_file_actions_addclose_iter, (VALUE)fops);
}

static VALUE
rb_fastspawn_pspawn(VALUE self, VALUE env, VALUE argv, VALUE options)
{
	int i, ret;
	int argc = RARRAY_LEN(argv);
	char *cargv[argc + 1];
	pid_t pid;
	posix_spawn_file_actions_t fops;
	posix_spawnattr_t attr;

	cargv[argc] = NULL;
	for(i = 0; i < argc; i++)
		cargv[i] = StringValuePtr(RARRAY_PTR(argv)[i]);

	posix_spawn_file_actions_init(&fops);
	fastspawn_file_actions_addclose(&fops, options);
	posix_spawn_file_actions_addopen(&fops, 2, "/dev/null", O_WRONLY, 0);

	posix_spawnattr_init(&attr);
#ifdef POSIX_SPAWN_USEVFORK
	posix_spawnattr_setflags(&attr, POSIX_SPAWN_USEVFORK);
#endif

	ret = posix_spawnp(&pid, cargv[0], &fops, &attr, cargv, environ);

	posix_spawn_file_actions_destroy(&fops);
	posix_spawnattr_destroy(&attr);

	if(ret != 0) {
		errno = ret;
		rb_sys_fail("posix_spawnp");
	}

	return INT2FIX(pid);
}

void
Init_fastspawn()
{
	rb_mFastSpawn = rb_define_module("FastSpawn");
	rb_define_method(rb_mFastSpawn, "_vspawn", rb_fastspawn_vspawn, 3);
	rb_define_method(rb_mFastSpawn, "_pspawn", rb_fastspawn_pspawn, 3);
}

/* vim: set noexpandtab sts=0 ts=4 sw=4: */
