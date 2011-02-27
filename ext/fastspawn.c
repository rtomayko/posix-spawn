#include <unistd.h>
#include <stdio.h>
#include "ruby.h"

/* module FastSpawn */
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

	/* return the pid as a Fixnum */
	return INT2FIX(pid);
}

void Init_fastspawn()
{
	rb_mFastSpawn = rb_define_module("FastSpawn");
	rb_define_method(rb_mFastSpawn, "vspawn", fastspawn_vspawn, -1);
}

/* vim: set noexpandtab sts=0 ts=8 sw=8: */
