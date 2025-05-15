//   ____  __   __        ______        __
//  / __ \/ /__/ /__ ___ /_  __/__ ____/ /
// / /_/ / / _  / -_|_-<_ / / / -_) __/ _ \
// \____/_/\_,_/\__/___(@)_/  \__/\__/_// /
//  ~~~ oldes.huhuman at gmail.com ~~~ /_/
//
// SPDX-License-Identifier: MIT
// =============================================================================
// Rebol/MathPresso experimental Rebol extension
// =============================================================================

#include "mathpresso.h"
extern "C" {
	#include "mathpresso-rebol-extension.h"
}

#include <stdio.h>
#include <stdlib.h>

#define COMMAND extern "C" int

#define FRM_IS_HANDLE(n, t)     (RXA_TYPE(frm,n) == RXT_HANDLE && RXA_HANDLE_TYPE(frm, n) == t)
#define FRM_IS_STRUCT(n)        (RXA_TYPE(frm,n) == RXT_STRUCT)
#define ARG_Is_MPContext(n)     FRM_IS_HANDLE(n, Handle_MPContext)
#define ARG_Is_MPExpression(n)  FRM_IS_HANDLE(n, Handle_MPExpression)
#define ARG_MPContext(n)        (ARG_Is_MPContext(n)    ? (MPContext*)   (RXA_HANDLE_CONTEXT(frm, n)->handle) : NULL)
#define ARG_MPExpression(n)     (ARG_Is_MPExpression(n) ? (MPExpression*)(RXA_HANDLE_CONTEXT(frm, n)->handle) : NULL)
#define ARG_Series(n)           (REBSER *)RXA_SERIES(frm, n)
#define ARG_Index(n)            RXA_INDEX(frm, n)

static char* err_buff[255]; // temporary buffer used to pass an exception messages to Rebol side
#define RETURN_ERROR(err)                    \
	snprintf((char*)err_buff, 254,"%s", err);\
	RXA_SERIES(frm, 1) = (void*)err_buff;    \
	return RXR_ERROR

#define RETURN_HANDLE(hob)                   \
	RXA_HANDLE(frm, 1)       = hob;          \
	RXA_HANDLE_TYPE(frm, 1)  = hob->sym;     \
	RXA_HANDLE_FLAGS(frm, 1) = hob->flags;   \
	RXA_TYPE(frm, 1) = RXT_HANDLE;           \
	return RXR_VALUE

#define RETURN_DOUBLE(d)                     \
	RXA_TYPE(frm, 1) = RXT_DECIMAL;          \
	RXA_DEC64(frm, 1) = (d);                 \
	return RXR_VALUE


using namespace mathpresso;

// By inheriting `OutputLog` one can create a way how to handle possible errors
// and report them to humans. The most interesting and used message type is
// `kMessageError`, because it signalizes an invalid expression. Other message
// types are used mostly for debugging.
struct MyOutputLog : public OutputLog {
	virtual void log(unsigned int type, unsigned int line, unsigned int column, const char* message, size_t size) {
		(void)line;
		(void)column;
		(void)size;

		if (type == kMessageError)
			printf("ERROR: %s\n", message);
		else
			printf("WARNING: %s\n", message);
	}
};

REBCNT  MPOptions = 0;

#define  MAX_VERBOSE_FLAGS (kOptionVerbose | kOptionDebugAst | kOptionDebugMachineCode | kOptionDebugCompiler)
#define  AST_VERBOSE_FLAGS (kOptionVerbose | kOptionDebugAst)
#define CODE_VERBOSE_FLAGS (kOptionVerbose | kOptionDebugMachineCode)

extern "C" {
	void* releaseMPExpression(void* hndl) {
		if (hndl != NULL) {
			MPExpression *mpe = (MPExpression*)hndl;
			debug_print("GC MPExpression %p, struct: %u\n", mpe->expression, mpe->struct_id);
			if (mpe->expression) {
				delete (mathpresso::Expression*)mpe->expression;
			}
		}
		return NULL;
	}
	void* releaseMPContext(void* hndl) {
		if (hndl != NULL) {
			MPContext *mpc = (MPContext *)hndl;
			if(mpc->context) { 
				debug_print("GC MPContext %p\n", mpc->context);
				delete (mathpresso::Context*)mpc->context;
			}
		}
		return NULL;
	}
}

COMMAND cmd_context(RXIFRM *frm, void *rctx) {
	REBSER *spec;
	REBHOB *hob = NULL;
	REBCNT i;
	MPContext *mpc;
	mathpresso::Context *ctx = NULL;

	spec = RXA_STRUCT_SPEC(frm, 1);
	if (spec == NULL || spec->series == NULL) {
		RETURN_ERROR("Bad struct specification!");
	}

	hob = RL_MAKE_HANDLE_CONTEXT(Handle_MPContext);
	if (hob == NULL) return RXR_NONE;

	mpc = (MPContext*)hob->data;
	mpc->context = ctx = new Context();
	mpc->struct_id = RXA_STRUCT_ID(frm, 1);
	mpc->bytes_needed = 0;

	debug_print("New MPContext: %p\n", ctx);

	ctx->addBuiltIns();

	REBSTI *info = (REBSTI *)BIN_HEAD(spec->series);
	REBSTF *field = (REBSTF *)info + 1;

	for (i = 0; i < info->count; ++i, ++field) {
		if (field->type == 10) {
			ctx->addVariable(cs_cast(RL_WORD_STRING(field->sym)), field->offset);
			mpc->bytes_needed += sizeof(REBDEC);
		}
	}
	RETURN_HANDLE(hob);
}

COMMAND cmd_compile(RXIFRM *frm, void *ctx) {	
	REBHOB *hob = NULL;
	REBSER *code;
	MPContext *mpc;
	MPExpression *mpe;
	mathpresso::Context    *mpCtx = NULL;
	mathpresso::Expression *mpExp = NULL;
	MyOutputLog outputLog;

	if (FRM_IS_STRUCT(1)) {
		cmd_context(frm, ctx);
	}

	mpc = ARG_MPContext(1);
	if (mpc == NULL) return RXR_NONE;

	mpCtx = (Context*)mpc->context;
	if (mpCtx == NULL) return RXR_NONE;

	code = ARG_Series(2);
	// if unicode, convert to UTF8...
	if(SERIES_WIDE(code) > 1)
		code = RL_ENCODE_UTF8_STRING(SERIES_DATA(code), SERIES_TAIL(code), TRUE, FALSE);

	// Create a new expression...
	hob = RL_MAKE_HANDLE_CONTEXT(Handle_MPExpression);
	if (hob == NULL) return RXR_NONE;
	mpe = (MPExpression*)hob->data;
	mpe->expression = mpExp = new Expression();
	mpe->struct_id = mpc->struct_id;
	mpe->bytes_needed = mpc->bytes_needed;
	debug_print("New MPExpression: %p for context: %p options: %u\n", mpExp, mpCtx, MPOptions);
	// And compile it...
	Error err = mpExp->compile(*mpCtx, SERIES_TEXT(code), MPOptions, &outputLog);
	if (err != kErrorOk) {
		RL_FREE_HANDLE_CONTEXT(hob);
		return RXR_NONE;
	}
	RETURN_HANDLE(hob);
}

COMMAND cmd_eval(RXIFRM *frm, void *ctx) {
	MPExpression *mpe;
	REBSER *ser;
	REBYTE *bin;
	REBU64  len;

	mpe = ARG_MPExpression(1);
	if(mpe == NULL) {
		RETURN_ERROR("Command needs a valid MPExpression handle!");
	}

	if (FRM_IS_STRUCT(2)) {
		if (mpe->struct_id != RXA_STRUCT_ID(frm, 2)) {
			RETURN_ERROR("Bad struct!");
		}
		len = RXA_STRUCT_LEN(frm, 2);
		bin = RXA_STRUCT_BIN(frm, 2);
	} else {
		ser = ARG_Series(2);
		if(VECT_TYPE(ser) != 11) {
			RETURN_ERROR("Command needs a vector with double values!");
		}
		len = (SERIES_TAIL(ser) - ARG_Index(2)) * sizeof(REBDEC);
		bin = SERIES_SKIP(ser, ARG_Index(2));
	}
	if (len < mpe->bytes_needed) {
		debug_print("Data bytes: %llu, needed: %llu\n", len, mpe->bytes_needed);
		RETURN_ERROR("Insufficient size of input data!");
	}

	Expression *e = (Expression*)mpe->expression;
	RETURN_DOUBLE(e->evaluate(bin));
}

COMMAND cmd_set_options(RXIFRM *frm, void *ctx) {
	REBU64 num = RXA_UINT64(frm,1);
	if (num > 0xFFFFu) return RXR_FALSE;
	MPOptions = (REBCNT)num;
	return RXR_TRUE;
}