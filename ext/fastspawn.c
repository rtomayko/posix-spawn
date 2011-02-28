#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <unistd.h>
#include "ruby.h"

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

static VALUE
rb_fastspawn_pspawn(VALUE self, VALUE env, VALUE argv, VALUE options)
{
	int i, ret;
	int argc = RARRAY_LEN(argv);
	char *cargv[argc + 1];
	pid_t pid;
	posix_spawn_file_actions_t fops;

	cargv[argc] = NULL;
	for(i = 0; i < argc; i++)
		cargv[i] = StringValuePtr(RARRAY_PTR(argv)[i]);

	posix_spawn_file_actions_init(&fops);
	posix_spawn_file_actions_addopen(&fops, 2, "/dev/null", O_WRONLY, 0);
	ret = posix_spawnp(&pid, cargv[0], &fops, NULL, cargv, environ);
	posix_spawn_file_actions_destroy(&fops);

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
