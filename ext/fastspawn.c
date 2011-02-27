#include <unistd.h>
#include <stdio.h>
#include <spawn.h>
#include "ruby.h"

extern char **environ;

static VALUE rb_mFastSpawn;

static VALUE
fastspawn_vspawn(int argc, VALUE *argv, VALUE self)
{
	int i;
	char *cargv[argc + 1];
	pid_t pid;

	cargv[argc] = NULL;
	for(i = 0; i < argc; i++)
		cargv[i] = StringValuePtr(argv[i]);

	pid = vfork();
	if(!pid) {
		execvp(cargv[0], cargv);
		_exit(1);
	}

	return INT2FIX(pid);
}

static VALUE
fastspawn_pspawn(int argc, VALUE *argv, VALUE self)
{
	int i;
	char *cargv[argc + 1];
	pid_t pid;

	cargv[argc] = NULL;
	for(i = 0; i < argc; i++)
		cargv[i] = StringValuePtr(argv[i]);

	posix_spawnp(&pid, cargv[0], NULL, NULL, cargv, environ);

	return INT2FIX(pid);
}

void
Init_fastspawn()
{
	rb_mFastSpawn = rb_define_module("FastSpawn");
	rb_define_method(rb_mFastSpawn, "vspawn", fastspawn_vspawn, -1);
	rb_define_method(rb_mFastSpawn, "pspawn", fastspawn_vspawn, -1);
}

/* vim: set noexpandtab sts=0 ts=8 sw=8: */
