#include <stdio.h>
#include "ruby.h"

/* module FastSpawn */
static VALUE rb_mFastSpawn;

static VALUE
fastspawn_vspawn(int argc, VALUE *argv, VALUE self)
{
	return Qnil;
}

void Init_fastspawn()
{
	rb_mFastSpawn = rb_define_module("FastSpawn");
	rb_define_method(rb_mFastSpawn, "vspawn", fastspawn_vspawn, -1);
}

/* vim: set noexpandtab sts=0 ts=8 sw=8: */
