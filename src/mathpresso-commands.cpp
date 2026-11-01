//   ____  __   __        ______        __
//  / __ \/ /__/ /__ ___ /_  __/__ ____/ /
// / /_/ / / _  / -_|_-<_ / / / -_) __/ _ \
// \____/_/\_,_/\__/___(@)_/  \__/\__/_// /
//  ~~~ oldes.huhuman at gmail.com ~~~ /_/
//
// Project: Rebol/MathPresso extension
// SPDX-License-Identifier: MIT
// =============================================================================
// Command implementations and handle callbacks.
//
// One function per command; the enum, the declarations, the dispatch table
// and the `_init` handler are all generated from mathpresso.reb.
//
// The generated header is included inside `extern "C"`, so every command and
// callback declared there keeps C linkage at its definition below.
//

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "mathpresso.h"
extern "C" {
	#include "gen-mathpresso.h"
}

using namespace mathpresso;

#ifndef STRUCT_TYPE_DOUBLE
#define STRUCT_TYPE_DOUBLE 10    // REBSTF type of a `double!` field
#endif

#define ARG_Is_MPContext(n)     FRM_IS_HANDLE(n, Handle_MPContext)
#define ARG_Is_MPExpression(n)  FRM_IS_HANDLE(n, Handle_MPExpression)
#define ARG_MPContext(n)        (ARG_Is_MPContext(n)    ? (MPContext*)   (RXA_HANDLE_CONTEXT(frm, n)->data) : NULL)
#define ARG_MPExpression(n)     (ARG_Is_MPExpression(n) ? (MPExpression*)(RXA_HANDLE_CONTEXT(frm, n)->data) : NULL)

#define RETURN_DOUBLE(d)                     \
	RXA_TYPE(frm, 1) = RXT_DECIMAL;          \
	RXA_DEC64(frm, 1) = (d);                 \
	return RXR_VALUE

static const char* ERR_BAD_STRUCT    = "Unusable struct argument!";
static const char* ERR_STRUCT_ID     = "Bad struct!";
static const char* ERR_RAW_STRUCT    = "Struct does not allow raw modification!";
static const char* ERR_NO_EXPRESSION = "Command needs a valid MPExpression handle!";
static const char* ERR_NOT_DOUBLES   = "Command needs a vector with double values!";
static const char* ERR_SHORT_DATA    = "Insufficient size of input data!";

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

static REBCNT MPOptions = 0;


//== handle callbacks =========================================================

// Both take the HOB (HANDLE_REQUIRES_HOB_ON_FREE).

int MPExpression_free(void *hndl) {
	REBHOB *hob = (REBHOB*)hndl;
	MPExpression *mpe;

	if (!hob || !(mpe = (MPExpression*)hob->data)) return 0;
	if (mpe->expression) {
		debug_print("GC MPExpression %p, struct: %u\n", mpe->expression, mpe->struct_id);
		delete (Expression*)mpe->expression;
		mpe->expression = NULL;
	}
	UNMARK_HOB(hob);
	return 0;
}

int MPContext_free(void *hndl) {
	REBHOB *hob = (REBHOB*)hndl;
	MPContext *mpc;

	if (!hob || !(mpc = (MPContext*)hob->data)) return 0;
	if (mpc->context) {
		debug_print("GC MPContext %p\n", mpc->context);
		delete (Context*)mpc->context;
		mpc->context = NULL;
	}
	UNMARK_HOB(hob);
	return 0;
}


//== commands =================================================================

COMMAND cmd_mathpresso_context(RXIFRM *frm, void *ctx) {
	RXISTRU    stru;
	REBSTF    *field;
	REBHOB    *hob;
	MPContext *mpc;
	Context   *mpCtx;
	REBCNT     i;

	// One lookup gives the spec id and the field list of THIS struct,
	// whether it is a root struct or a nested view.
	if (!RXA_STRUCT_INFO(frm, 1, &stru)) RETURN_ERROR(ERR_BAD_STRUCT);

	hob = RL_MAKE_HANDLE_CONTEXT(Handle_MPContext);
	if (hob == NULL) return RXR_NONE;

	mpc = (MPContext*)hob->data;
	mpc->context = mpCtx = new Context();
	mpc->struct_id = stru.id;
	mpc->bytes_needed = 0;

	debug_print("New MPContext: %p\n", (void*)mpCtx);

	mpCtx->add_builtins();

	field = RXI_STRUCT_FIELDS(&stru);
	for (i = 0; i < stru.count; ++i, ++field) {
		if (field->type == STRUCT_TYPE_DOUBLE) {
			mpCtx->add_variable(cs_cast(RL_WORD_STRING(field->sym)), field->offset);
			mpc->bytes_needed += sizeof(REBDEC);
		}
	}
	RETURN_HANDLE(hob);
}

COMMAND cmd_mathpresso_compile(RXIFRM *frm, void *ctx) {
	REBHOB       *hob;
	REBSER       *code;
	MPContext    *mpc;
	MPExpression *mpe;
	Context      *mpCtx;
	Expression   *mpExp;
	MyOutputLog   outputLog;

	if (RXA_TYPE(frm, 1) == RXT_STRUCT) {
		// Replaces the struct in arg 1 with a temporary MPContext handle.
		int result = cmd_mathpresso_context(frm, ctx);
		if (result != RXR_VALUE) return result;
	}

	mpc = ARG_MPContext(1);
	if (mpc == NULL) return RXR_NONE;

	mpCtx = (Context*)mpc->context;
	if (mpCtx == NULL) return RXR_NONE;

	// Strings are always UTF-8 encoded now.
	code = (REBSER*)RXA_SERIES(frm, 2);

	// Create a new expression...
	hob = RL_MAKE_HANDLE_CONTEXT(Handle_MPExpression);
	if (hob == NULL) return RXR_NONE;
	mpe = (MPExpression*)hob->data;
	mpe->expression = mpExp = new Expression();
	mpe->struct_id = mpc->struct_id;
	mpe->bytes_needed = mpc->bytes_needed;
	debug_print("New MPExpression: %p for context: %p options: %u\n", (void*)mpExp, (void*)mpCtx, MPOptions);

	// And compile it...
	Error err = mpExp->compile(*mpCtx, SERIES_TEXT(code), MPOptions, &outputLog);
	if (err != kErrorOk) {
		delete mpExp;
		mpe->expression = NULL;
		RL_FREE_HANDLE_CONTEXT(hob);
		return RXR_NONE;
	}
	RETURN_HANDLE(hob);
}

COMMAND cmd_mathpresso_eval(RXIFRM *frm, void *ctx) {
	MPExpression *mpe;
	REBYTE *bin;
	REBU64  len;

	mpe = ARG_MPExpression(1);
	if (mpe == NULL || mpe->expression == NULL) RETURN_ERROR(ERR_NO_EXPRESSION);

	if (RXA_TYPE(frm, 2) == RXT_STRUCT) {
		RXISTRU stru;
		// Data and size of THIS struct - a nested view included.
		if (!RXA_STRUCT_INFO(frm, 2, &stru)) RETURN_ERROR(ERR_BAD_STRUCT);
		if (mpe->struct_id != stru.id)        RETURN_ERROR(ERR_STRUCT_ID);
		// The expression writes into the data.
		if (!RXI_STRUCT_WRITABLE(&stru))      RETURN_ERROR(ERR_RAW_STRUCT);
		len = stru.size;
		bin = stru.data;
	} else {
		REBSER *ser   = RXA_VECTOR_SERIES(frm, 2);
		REBCNT  index = RXA_VECTOR_INDEX(frm, 2);
		if (RXI_VECTOR_TYPE(RXA_VECTOR_INFO(frm, 2)) != VTSF64) RETURN_ERROR(ERR_NOT_DOUBLES);
		len = (REBU64)(SERIES_TAIL(ser) - index) * sizeof(REBDEC);
		bin = SERIES_SKIP(ser, index);
	}
	if (len < mpe->bytes_needed) {
		debug_print("Data bytes: %llu, needed: %u\n", (unsigned long long)len, mpe->bytes_needed);
		RETURN_ERROR(ERR_SHORT_DATA);
	}

	RETURN_DOUBLE(((Expression*)mpe->expression)->evaluate(bin));
}

COMMAND cmd_mathpresso_set_options(RXIFRM *frm, void *ctx) {
	REBU64 num = RXA_UINT64(frm, 1);
	if (num > 0xFFFFu) return RXR_FALSE;
	MPOptions = (REBCNT)num;
	return RXR_TRUE;
}