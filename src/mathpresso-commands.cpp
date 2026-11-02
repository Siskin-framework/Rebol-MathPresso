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
#include <string.h>
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
static const char* ERR_NOT_STRUCTS   = "/each needs a vector of structs!";

// Receives messages from MathPresso's parser, optimizer and compiler.
//
// The first `kMessageError` is kept, with its position, so that `compile` can
// raise it as a Rebol error. Everything else is debug output, which appears
// only when requested using `set-options`, and is printed.
struct MyOutputLog : public OutputLog {
	char error[256];
	bool has_error;

	MyOutputLog() : has_error(false) { error[0] = 0; }

	virtual void log(unsigned int type, unsigned int line, unsigned int column, const char* message, size_t size) {
		if (type == kMessageError) {
			if (has_error) return;
			has_error = true;
			// Line 0 means MathPresso has no position for the message.
			if (line > 0)
				snprintf(error, sizeof(error), "%.*s (at %u:%u)", (int)size, message, line, column);
			else
				snprintf(error, sizeof(error), "%.*s", (int)size, message);
			return;
		}
		printf("WARNING: %.*s\n", (int)size, message);
	}
};

// Used when compilation fails without logging a message (e.g. when asmjit
// fails to generate code).
static const char* Error_Text(Error err) {
	switch (err) {
	case kErrorNoMemory:            return "Out of memory!";
	case kErrorInvalidArgument:     return "Invalid argument!";
	case kErrorInvalidState:        return "Invalid state!";
	case kErrorNoExpression:        return "No expression was given!";
	case kErrorInvalidSyntax:       return "Invalid syntax!";
	case kErrorSymbolNotFound:      return "Symbol not found!";
	case kErrorSymbolAlreadyExists: return "Symbol already exists!";
	default:                        return "Failed to compile the expression!";
	}
}

// The message of a failed compilation. Static, because the interpreter reads
// it only after the command has returned.
static char MPError[256];

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

// Returns a newly allocated copy of a constant's name (free it), or NULL
// when the value cannot name a constant.
//
// A word arrives as its canonical symbol, so its spelling is that of the
// first casing Rebol met - `Scale` may come back as `scale`. MathPresso
// names are case-sensitive, so a ref! (`@Scale`) is accepted for a name
// which must be kept exactly as written.
static char* Constant_Name(REBCNT type, RXIARG *val) {
	if (type == RXT_WORD || type == RXT_SET_WORD || type == RXT_LIT_WORD)
		return (char*)RL_WORD_STRING(val->int32a); // allocates a new string!

	if (type == RXT_REF) {
		// Strings are UTF-8 encoded byte series.
		REBSER *ser   = (REBSER*)val->series;
		REBCNT  index = val->index;
		REBCNT  tail  = SERIES_TAIL(ser);
		REBCNT  len   = index < tail ? tail - index : 0;
		char   *str;
		if (len == 0) return NULL;
		str = (char*)malloc(len + 1);
		if (!str) return NULL;
		memcpy(str, SERIES_SKIP(ser, index), len);
		str[len] = 0;
		return str;
	}
	return NULL;
}

// Adds name/number pairs from a block (starting at `index`) as constants.
// Returns NULL on success, otherwise the error message (in MPError).
static const char* Add_Constants(Context *mpCtx, REBSER *blk, REBCNT index) {
	REBCNT tail = (REBCNT)RL_SERIES(blk, RXI_SER_TAIL);
	RXIARG name, value;
	REBCNT name_type, value_type;
	char  *str;
	double num;
	Error err;

	for (REBCNT i = index; i < tail; i += 2) {
		name_type = RL_GET_VALUE(blk, i, &name);
		str = Constant_Name(name_type, &name);
		if (!str) return "Constant name must be a word or ref!";

		value_type = (i + 1 < tail) ? RL_GET_VALUE(blk, i + 1, &value) : RXT_END;
		if (value_type == RXT_INTEGER)      num = (double)value.int64;
		else if (value_type == RXT_DECIMAL) num = value.dec64;
		else {
			snprintf(MPError, sizeof(MPError), "Constant `%s` needs a number!", str);
			free(str);
			return MPError;
		}

		// The name is copied by MathPresso.
		err = mpCtx->add_constant(str, num);
		if (err != kErrorOk) {
			if (err == kErrorSymbolAlreadyExists)
				snprintf(MPError, sizeof(MPError), "Constant `%s` is already defined!", str);
			else
				snprintf(MPError, sizeof(MPError), "Constant `%s`: %s", str, Error_Text(err));
			free(str);
			return MPError;
		}
		free(str);
	}
	return NULL;
}

// Creates a MPContext handle for the struct in argument 1 and returns it
// in argument 1. Constants are added when `consts` is not NULL.
//
// Shared by `context` and by `compile` given a struct, which is why the
// constants are passed in rather than read from the frame: the two commands
// have different arguments after the first one.
static int Make_MPContext(RXIFRM *frm, REBSER *consts, REBCNT index) {
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

	// After the variables, so a constant cannot shadow a struct field.
	if (consts) {
		const char *msg = Add_Constants(mpCtx, consts, index);
		if (msg) {
			delete mpCtx;
			mpc->context = NULL;
			RL_FREE_HANDLE_CONTEXT(hob);
			RETURN_ERROR(msg);
		}
	}
	RETURN_HANDLE(hob);
}

// Arguments: 1 = spec, 2 = /with, 3 = constants.
COMMAND cmd_mathpresso_context(RXIFRM *frm, void *ctx) {
	if (RXA_REF(frm, 2))
		return Make_MPContext(frm, (REBSER*)RXA_SERIES(frm, 3), RXA_INDEX(frm, 3));
	return Make_MPContext(frm, NULL, 0);
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
		int result = Make_MPContext(frm, NULL, 0);
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
		snprintf(MPError, sizeof(MPError), "%s", outputLog.has_error ? outputLog.error : Error_Text(err));
		RETURN_ERROR(MPError);
	}
	RETURN_HANDLE(hob);
}

// eval/each: evaluates the expression for every struct of a vector of
// structs, starting at the vector's index, in one C loop. Returns the result
// of the last evaluation, or none when there was nothing to evaluate.
//
// Arguments: 2 = variables, 3 = /each, 4 = /part, 5 = count.
static int Eval_Each(RXIFRM *frm, MPExpression *mpe) {
	REBSER *ser, *fields;
	REBSTI *info;
	REBYTE *data;
	REBCNT  index, tail, wide, count, n;
	double  result = 0.0;

	if (RXA_TYPE(frm, 2) != RXT_VECTOR || RXI_VECTOR_TYPE(RXA_VECTOR_INFO(frm, 2)) != VTSTRUCT)
		RETURN_ERROR(ERR_NOT_STRUCTS);

	ser = RXA_VECTOR_SERIES(frm, 2);
	// A vector of structs keeps its element's field list in the series link
	// (see VAL_VEC_STRUCT), so the elements are checked like a struct would be.
	fields = ser->series;
	if (fields == NULL) RETURN_ERROR(ERR_BAD_STRUCT);
	info = FIELDS_INFO(fields);
	if (info->id != mpe->struct_id) RETURN_ERROR(ERR_STRUCT_ID);
	// The expression writes into the data.
	if (info->flags & (STRUCT_FLAG_MARK | STRUCT_FLAG_PROTECTED)) RETURN_ERROR(ERR_RAW_STRUCT);

	// The element size is kept as the series width.
	wide = SERIES_WIDE(ser);
	if (wide < mpe->bytes_needed) RETURN_ERROR(ERR_SHORT_DATA);

	index = RXA_VECTOR_INDEX(frm, 2);
	tail  = SERIES_TAIL(ser);
	count = index < tail ? tail - index : 0;
	if (RXA_REF(frm, 4)) {
		i64 part = RXA_INT64(frm, 5);
		if (part < 0) part = 0;
		if ((u64)part < count) count = (REBCNT)part;
	}
	if (count == 0) return RXR_NONE;

	Expression *e = (Expression*)mpe->expression;
	data = SERIES_SKIP(ser, index);
	for (n = 0; n < count; n++, data += wide) {
		result = e->evaluate(data);
	}
	RETURN_DOUBLE(result);
}

COMMAND cmd_mathpresso_eval(RXIFRM *frm, void *ctx) {
	MPExpression *mpe;
	REBYTE *bin;
	REBU64  len;

	mpe = ARG_MPExpression(1);
	if (mpe == NULL || mpe->expression == NULL) RETURN_ERROR(ERR_NO_EXPRESSION);

	if (RXA_REF(frm, 3)) return Eval_Each(frm, mpe);

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
