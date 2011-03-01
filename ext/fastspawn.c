/* we want GNU extensions like POSIX_SPAWN_USEVFORK */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <ruby.h>

#ifdef RUBY_VM
#include <ruby/st.h>
#else
#include <node.h>
#include <st.h>
#endif

#ifndef RARRAY_LEN
#define RARRAY_LEN(ary) RARRAY(ary)->len
#endif
#ifndef RARRAY_PTR
#define RARRAY_PTR(ary) RARRAY(ary)->ptr
#endif
#ifndef RHASH_SIZE
#define RHASH_SIZE(hash) RHASH(hash)->tbl->num_entries
#endif

#ifdef __APPLE__
#include <crt_externs.h>
#define environ (*_NSGetEnviron())
#else
extern char **environ;
#endif

static VALUE rb_mFastSpawn;

/* Determine the fd number for a Ruby object VALUE.
 *
 * obj - This can be any valid Ruby object, but only the following return
 *       an actual fd number:
 *         - The symbols :in, :out, or :err for fds 0, 1, or 2.
 *         - An IO object. (IO#fileno is returned)
 *         - A Fixnum.
 *
 * Returns the fd number >= 0 if one could be established, or -1 if the object
 * does not map to an fd.
 */
static int
fastspawn_obj_to_fd(VALUE obj)
{
	int fd = -1;
	switch (TYPE(obj)) {
		case T_FIXNUM:
			/* Fixnum fd number */
			fd = FIX2INT(obj);
			break;

		case T_SYMBOL:
			/* (:in|:out|:err) */
			if      (SYM2ID(obj) == rb_intern("in"))   fd = 0;
			else if (SYM2ID(obj) == rb_intern("out"))  fd = 1;
			else if (SYM2ID(obj) == rb_intern("err"))  fd = 2;
			break;

		case T_FILE:
			/* IO object */
			fd = FIX2INT(rb_funcall(obj, rb_intern("fileno"), 0));
			break;

		case T_OBJECT:
			/* some other object */
			if (rb_respond_to(obj, rb_intern("to_io"))) {
				obj = rb_funcall(obj, rb_intern("to_io"), 0);
				fd = FIX2INT(rb_funcall(obj, rb_intern("fileno"), 0));
			}
			break;
	}
	return fd;
}

/*
 * Hash iterator that sets up the posix_spawn_file_actions_t with addclose
 * operations. Only hash pairs whose value is :close are processed. Keys may
 * be the :in, :out, :err, an IO object, or a Fixnum fd number.
 *
 * Returns ST_DELETE when an addclose operation was added; ST_CONTINUE when
 * no operation was performed.
 */
static int
fastspawn_file_actions_addclose(VALUE key, VALUE val, posix_spawn_file_actions_t *fops)
{
	int fd;

	/* we only care about { (IO|FD|:in|:out|:err) => :close } */
	if (TYPE(val) != T_SYMBOL || SYM2ID(val) != rb_intern("close"))
		return ST_CONTINUE;

	fd  = fastspawn_obj_to_fd(key);
	if (fd >= 0) {
		posix_spawn_file_actions_addclose(fops, fd);
		return ST_DELETE;
	} else {
		return ST_CONTINUE;
	}
}

/*
 * Hash iterator that sets up the posix_spawn_file_actions_t with adddup2 +
 * clone operations for all redirects. Only hash pairs whose key and value
 * represent fd numbers are processed.
 *
 * Returns ST_DELETE when an adddup2 operation was added; ST_CONTINUE when
 * no operation was performed.
 */
static int
fastspawn_file_actions_reopen(VALUE key, VALUE val, posix_spawn_file_actions_t *fops)
{
	int fd, newfd;

	newfd = fastspawn_obj_to_fd(key);
	if (newfd < 0)
		return ST_CONTINUE;

	fd = fastspawn_obj_to_fd(val);
	if (fd < 0)
		return ST_CONTINUE;

	posix_spawn_file_actions_adddup2(fops, fd, newfd);
	posix_spawn_file_actions_addclose(fops, fd);
	return ST_DELETE;
}

/*
 * Main entry point for iterating over the options hash to perform file actions.
 * This function dispatches to the addclose and adddup2 functions, stopping once
 * an operation was added.
 *
 * Returns ST_DELETE if one of the handlers performed an operation; ST_CONTINUE
 * if not.
 */
static int
fastspawn_file_actions_operations_iter(VALUE key, VALUE val, posix_spawn_file_actions_t *fops)
{
	int act;

	act = fastspawn_file_actions_addclose(key, val, fops);
	if (act != ST_CONTINUE) return act;

	act = fastspawn_file_actions_reopen(key, val, fops);
	if (act != ST_CONTINUE) return act;

	return ST_CONTINUE;
}

/*
 * Initialize the posix_spawn_file_actions_t structure and add operations from
 * the options hash. Keys in the options Hash that are processed by handlers are
 * removed.
 *
 * Returns nothing.
 */
static void
fastspawn_file_actions_init(posix_spawn_file_actions_t *fops, VALUE options)
{
	posix_spawn_file_actions_init(fops);
	rb_hash_foreach(options, fastspawn_file_actions_operations_iter, (VALUE)fops);
}

static int
each_env_check_i(VALUE key, VALUE val, VALUE arg)
{
	StringValuePtr(key);
	if (!NIL_P(val)) StringValuePtr(val);
	return ST_CONTINUE;
}

static int
each_env_i(VALUE key, VALUE val, VALUE arg)
{
	char *name = StringValuePtr(key);
	size_t len = strlen(name);

	/*
	 * Delete any existing values for this variable before inserting the new value.
	 * This implementation was copied from glibc's unsetenv().
	 */
	char **ep = (char **)arg;
	while (*ep != NULL)
		if (!strncmp (*ep, name, len) && (*ep)[len] == '=')
		{
			/* Found it.  Remove this pointer by moving later ones back.  */
			char **dp = ep;

			do
				dp[0] = dp[1];
			while (*dp++);
			/* Continue the loop in case NAME appears again.  */
		}
		else
			++ep;

	/*
	 * Insert the new value if we have one. We can assume there is space
	 * at the end of the list, since ep was preallocated to be big enough
	 * for the new entries.
	 */
	if (RTEST(val)) {
		char **ep = (char **)arg;
		char *cval = StringValuePtr(val);

		size_t cval_len = strlen(cval);
		size_t ep_len = len + 1 + cval_len + 1; /* +2 for null terminator and '=' separator */

		/* find the last entry */
		while (*ep != NULL) ++ep;
		*ep = malloc(ep_len);

		strncpy(*ep, name, len);
		(*ep)[len] = '=';
		strncpy(*ep + len + 1, cval, cval_len);
		(*ep)[ep_len-1] = 0;
	}

	return ST_CONTINUE;
}

/*
 * FastSpawn#_pspawn(env, argv, options)
 *
 * env     - Hash of the new environment.
 * argv    - The [[cmdname, argv0], argv1, ...] exec array.
 * options - The options hash with fd redirect and close operations.
 *
 * Returns the pid of the newly spawned process.
 */
static VALUE
rb_fastspawn_pspawn(VALUE self, VALUE env, VALUE argv, VALUE options)
{
	int i, ret;
	long argc = RARRAY_LEN(argv);
	char **envp = NULL;
	char *cargv[argc + 1];
	VALUE cmdname;
	char *file;
	pid_t pid;
	posix_spawn_file_actions_t fops;
	posix_spawnattr_t attr;

	if (RTEST(env)) {
		/*
		 * Make sure env is a hash, and all keys and values are strings.
		 * We do this before allocating space for the new environment to
		 * prevent a leak when raising an exception after the calloc() below.
		 */
		Check_Type(env, T_HASH);
		rb_hash_foreach(env, each_env_check_i, 0);

		if (RHASH_SIZE(env) > 0) {
			char **curr = environ;
			int size = 0;
			if (curr) {
				while (*curr != NULL) ++curr, ++size;
			}

			char **new_env = calloc(size+RHASH_SIZE(env)+1, sizeof(char*));
			for (i = 0; i < size; i++) {
				new_env[i] = strdup(environ[i]);
			}
			envp = new_env;

			rb_hash_foreach(env, each_env_i, (VALUE)envp);
		}
	}

	/* argv is a [[cmdname, argv0], argv1, argvN, ...] array. */
	cmdname = RARRAY_PTR(argv)[0];
	file = StringValuePtr(RARRAY_PTR(cmdname)[0]);
	cargv[0] = StringValuePtr(RARRAY_PTR(cmdname)[1]);
	for (i = 1; i < argc; i++)
		cargv[i] = StringValuePtr(RARRAY_PTR(argv)[i]);
	cargv[argc] = NULL;

	fastspawn_file_actions_init(&fops, options);

	posix_spawnattr_init(&attr);
#if defined(POSIX_SPAWN_USEVFORK) || defined(__linux__)
	/* Force USEVFORK on linux. If this is undefined, it's probably because
	 * you forgot to define _GNU_SOURCE at the top of this file.
	 */
	posix_spawnattr_setflags(&attr, POSIX_SPAWN_USEVFORK);
#endif

	ret = posix_spawnp(&pid, file, &fops, &attr, cargv, envp ? envp : environ);

	posix_spawn_file_actions_destroy(&fops);
	posix_spawnattr_destroy(&attr);
	if (envp) {
		char **ep = envp;
		while (*ep != NULL) free(*ep), ++ep;
		free(envp);
	}

	if (ret != 0) {
		errno = ret;
		rb_sys_fail("posix_spawnp");
	}

	return INT2FIX(pid);
}

void
Init_fastspawn()
{
	rb_mFastSpawn = rb_define_module("FastSpawn");
	rb_define_method(rb_mFastSpawn, "_pspawn", rb_fastspawn_pspawn, 3);
}

/* vim: set noexpandtab sts=0 ts=4 sw=4: */
