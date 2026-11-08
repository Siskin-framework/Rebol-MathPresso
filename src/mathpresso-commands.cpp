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
#include <cmath>
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
static const char* ERR_BAD_OPTIONS   = "Compilation flags must be in range 0 - 65535!";
static const char* ERR_SHORT_BUFFER  = "render/with needs a vector of 64-bit decimals with a value for every pixel!";
static const char* ERR_NO_PIXELS     = "render needs an expression compiled with a context made with /pixels!";

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

//== extra functions ==========================================================

// Functions MathPresso does not have built in. They are plain C functions
// called from the compiled code; all are pure, so a call with constant
// arguments is evaluated already when the expression is compiled.
//
// The wrappers are needed because the <cmath> functions are overloaded, so
// their address is ambiguous.

static double F_cbrt(double x)   { return std::cbrt(x); }
static double F_exp2(double x)   { return std::exp2(x); }
static double F_expm1(double x)  { return std::expm1(x); }
static double F_log1p(double x)  { return std::log1p(x); }
static double F_erf(double x)    { return std::erf(x); }
static double F_erfc(double x)   { return std::erfc(x); }
static double F_tgamma(double x) { return std::tgamma(x); }
static double F_lgamma(double x) { return std::lgamma(x); }
static double F_sign(double x)   { return (double)((x > 0) - (x < 0)); }
// A pseudo random value in [0, 1) - the same for the same input.
static double F_hash(double x)   { double v = std::sin(x * 12.9898) * 43758.5453; return v - std::floor(v); }
static double F_fmod(double x, double y)    { return std::fmod(x, y); }
static double F_step(double edge, double x) { return x < edge ? 0.0 : 1.0; }
static double F_clamp(double x, double lo, double hi) { return x < lo ? lo : (x > hi ? hi : x); }
static double F_mix(double a, double b, double t)     { return a + (b - a) * t; }
static double F_smoothstep(double e0, double e1, double x) {
	double t = (x - e0) / (e1 - e0);
	t = t < 0 ? 0 : (t > 1 ? 1 : t);
	return t * t * (3 - 2 * t);
}

static const struct {
	const char  *name;
	void        *func;
	unsigned int args;
} MPFunctions[] = {
	{"cbrt",       (void*)F_cbrt,       kFunctionArg1},
	{"exp2",       (void*)F_exp2,       kFunctionArg1},
	{"expm1",      (void*)F_expm1,      kFunctionArg1},
	{"log1p",      (void*)F_log1p,      kFunctionArg1},
	{"erf",        (void*)F_erf,        kFunctionArg1},
	{"erfc",       (void*)F_erfc,       kFunctionArg1},
	{"tgamma",     (void*)F_tgamma,     kFunctionArg1},
	{"lgamma",     (void*)F_lgamma,     kFunctionArg1},
	{"sign",       (void*)F_sign,       kFunctionArg1},
	{"hash",       (void*)F_hash,       kFunctionArg1},
	{"fmod",       (void*)F_fmod,       kFunctionArg2},
	{"step",       (void*)F_step,       kFunctionArg2},
	{"clamp",      (void*)F_clamp,      kFunctionArg3},
	{"mix",        (void*)F_mix,        kFunctionArg3},
	{"smoothstep", (void*)F_smoothstep, kFunctionArg3},
};

// A name already used by a variable or a constant is skipped, not an error:
// those come from the user and win over the extra functions.
static void Add_Functions(Context *mpCtx) {
	for (size_t i = 0; i < sizeof(MPFunctions) / sizeof(MPFunctions[0]); i++) {
		mpCtx->add_function(MPFunctions[i].name, MPFunctions[i].func,
			MPFunctions[i].args | kFunctionNoSideEffects);
	}
}

// Adds a plain `double!` field as a variable. Returns FALSE with the message
// in MPError when the name is already taken (e.g. by `v_1` of an array `v`
// declared before it). MathPresso copies the name, so ours is freed.
static bool Add_Field(Context *mpCtx, REBSTF *field, unsigned int flags) {
	char  *name = (char*)RL_WORD_STRING(field->sym); // allocates a new string!
	Error  err  = mpCtx->add_variable(name, (int)field->offset, flags);

	if (err != kErrorOk) {
		if (err == kErrorSymbolAlreadyExists)
			snprintf(MPError, sizeof(MPError), "Variable `%s` is already defined!", name);
		else
			snprintf(MPError, sizeof(MPError), "Variable `%s`: %s", name, Error_Text(err));
	}
	free(name);
	return err == kErrorOk;
}

// Adds every element of a `double!` array field as a variable named
// `<field>_<n>` (1-based). Returns FALSE with the message in MPError when a
// name is already taken (e.g. by a plain field called `v_1`).
static bool Add_Array_Field(Context *mpCtx, REBSTF *field, unsigned int flags) {
	char  *base = (char*)RL_WORD_STRING(field->sym); // allocates a new string!
	char   name[256];
	Error  err;

	for (REBCNT n = 0; n < field->dimension; n++) {
		snprintf(name, sizeof(name), "%s_%u", base, n + 1);
		err = mpCtx->add_variable(name, (int)(field->offset + n * field->size), flags);
		if (err != kErrorOk) {
			if (err == kErrorSymbolAlreadyExists)
				snprintf(MPError, sizeof(MPError), "Variable `%s` of array field `%s` is already defined!", name, base);
			else
				snprintf(MPError, sizeof(MPError), "Variable `%s`: %s", name, Error_Text(err));
			free(base);
			return false;
		}
	}
	free(base);
	return true;
}

// Fields named in the `/read-only` block. A word arrives as its canonical
// symbol, which is also what a struct field's `sym` holds, so they compare
// directly; an array's name stands for all its elements.
typedef struct {
	REBSER *block;  // NULL = no field is read-only
	REBCNT  index;
} ReadOnlyList;

static bool Is_Read_Only(const ReadOnlyList *ro, REBCNT sym) {
	RXIARG val;
	REBCNT type, tail;
	if (!ro->block) return false;
	tail = (REBCNT)RL_SERIES(ro->block, RXI_SER_TAIL);
	for (REBCNT i = ro->index; i < tail; i++) {
		type = RL_GET_VALUE(ro->block, i, &val);
		if ((type == RXT_WORD || type == RXT_SET_WORD || type == RXT_LIT_WORD) && (REBCNT)val.int32a == sym)
			return true;
	}
	return false;
}

// Every name in the block must be a word naming a `double!` field. Returns
// NULL when it does, otherwise the error message (in MPError).
static const char* Check_Read_Only(const ReadOnlyList *ro, RXISTRU *stru) {
	RXIARG  val;
	REBCNT  type, tail, i, f;
	REBSTF *field;
	if (!ro->block) return NULL;
	tail = (REBCNT)RL_SERIES(ro->block, RXI_SER_TAIL);
	for (i = ro->index; i < tail; i++) {
		type = RL_GET_VALUE(ro->block, i, &val);
		if (type != RXT_WORD && type != RXT_SET_WORD && type != RXT_LIT_WORD)
			return "Read-only fields must be named by words!";
		field = RXI_STRUCT_FIELDS(stru);
		for (f = 0; f < stru->count; ++f, ++field) {
			if (field->type == STRUCT_TYPE_DOUBLE && field->sym == (REBCNT)val.int32a) break;
		}
		if (f >= stru->count) {
			char *name = (char*)RL_WORD_STRING(val.int32a); // allocates a new string!
			snprintf(MPError, sizeof(MPError), "No double! field `%s` to make read-only!", name);
			free(name);
			return MPError;
		}
	}
	return NULL;
}

// The pixel variables of a context made with /pixels, in this order, after
// the struct's own bytes: the pixel's column and row (read-only), its
// colour, and its value in the buffer of render/with.
static const char* const PixelVars[] = {"x", "y", "r", "g", "b", "a", "buf"};
#define PIXEL_VARS 7

// Adds the pixel variables at `offset`. Returns FALSE with the message in
// MPError when a name is already taken by a field of the struct.
static bool Add_Pixel_Vars(Context *mpCtx, REBCNT offset) {
	for (int i = 0; i < PIXEL_VARS; i++) {
		Error err = mpCtx->add_variable(PixelVars[i], (int)(offset + i * sizeof(REBDEC)),
			i < 2 ? kVariableRO : kVariableRW);
		if (err != kErrorOk) {
			if (err == kErrorSymbolAlreadyExists)
				snprintf(MPError, sizeof(MPError), "Field `%s` clashes with a pixel variable of /pixels!", PixelVars[i]);
			else
				snprintf(MPError, sizeof(MPError), "Variable `%s`: %s", PixelVars[i], Error_Text(err));
			return false;
		}
	}
	return true;
}

// Creates a MPContext handle for the struct in argument 1 and returns it
// in argument 1. Constants are added when `consts` is not NULL, and the
// fields named in `ro` become read-only. With `pixels`, the variables of
// `render` are added after the struct's own bytes.
//
// Shared by `context` and by `compile` given a struct, which is why the
// blocks are passed in rather than read from the frame: the two commands
// have different arguments after the first one.
static int Make_MPContext(RXIFRM *frm, REBSER *consts, REBCNT index, const ReadOnlyList *ro, bool pixels) {
	RXISTRU    stru;
	REBSTF    *field;
	REBHOB    *hob;
	MPContext *mpc;
	Context   *mpCtx;
	REBCNT     i;
	const char *msg = NULL;
	unsigned int flags;

	// One lookup gives the spec id and the field list of THIS struct,
	// whether it is a root struct or a nested view.
	if (!RXA_STRUCT_INFO(frm, 1, &stru)) RETURN_ERROR(ERR_BAD_STRUCT);
	if ((msg = Check_Read_Only(ro, &stru))) RETURN_ERROR(msg);

	hob = RL_MAKE_HANDLE_CONTEXT(Handle_MPContext);
	if (hob == NULL) return RXR_NONE;

	mpc = (MPContext*)hob->data;
	mpc->context = mpCtx = new Context();
	mpc->struct_id = stru.id;
	mpc->bytes_needed = 0;
	// Cleared by the first writable variable. With none, no expression of
	// this context can write into the data.
	mpc->read_only = 1;
	mpc->pixels = NO_PIXELS;

	debug_print("New MPContext: %p\n", (void*)mpCtx);

	mpCtx->add_builtins();

	// `bytes_needed` is how far into the data the expression may read or
	// write: the end of the last double variable, not their total size -
	// fields of other types before or between them take space too.
	field = RXI_STRUCT_FIELDS(&stru);
	for (i = 0; i < stru.count; ++i, ++field) {
		if (field->type != STRUCT_TYPE_DOUBLE) continue;
		REBCNT end = field->offset + (field->array ? field->dimension : 1) * sizeof(REBDEC);
		if (end > mpc->bytes_needed) mpc->bytes_needed = end;

		flags = Is_Read_Only(ro, field->sym) ? kVariableRO : kVariableRW;
		if (flags == kVariableRW) mpc->read_only = 0;

		// MathPresso has no indexing, so every element of an array field
		// becomes its own variable: `v [double! [3]]` is `v_1 v_2 v_3`
		// (1-based, like Rebol's `v/1`).
		if (field->array ? !Add_Array_Field(mpCtx, field, flags) : !Add_Field(mpCtx, field, flags)) {
			msg = MPError;
			goto fail;
		}
	}

	// The pixel variables go after the whole struct (aligned for doubles),
	// so `render` can copy the struct's bytes in front of them as they are.
	if (pixels) {
		mpc->pixels = (REBCNT)((stru.size + 7) & ~(REBCNT)7);
		if (!Add_Pixel_Vars(mpCtx, mpc->pixels)) {
			msg = MPError;
			goto fail;
		}
		mpc->bytes_needed = mpc->pixels + PIXEL_VARS * sizeof(REBDEC);
		mpc->read_only = 0;   // r g b a are written
	}

	// After the variables, so a constant cannot shadow a struct field.
	if (consts && (msg = Add_Constants(mpCtx, consts, index))) goto fail;

	// Last, so that a struct field or a constant of the same name wins over
	// an extra function (e.g. a field called `step`).
	Add_Functions(mpCtx);

	RETURN_HANDLE(hob);

fail:
	delete mpCtx;
	mpc->context = NULL;
	RL_FREE_HANDLE_CONTEXT(hob);
	RETURN_ERROR(msg);
}

// Arguments: 1 = spec, 2 = /with, 3 = constants, 4 = /read-only, 5 = fields,
// 6 = /pixels.
COMMAND cmd_mathpresso_context(RXIFRM *frm, void *ctx) {
	bool pixels = RXA_REF(frm, 6) != 0;
	ReadOnlyList ro = { NULL, 0 };
	if (RXA_REF(frm, 4)) {
		ro.block = (REBSER*)RXA_SERIES(frm, 5);
		ro.index = RXA_INDEX(frm, 5);
	}
	if (RXA_REF(frm, 2))
		return Make_MPContext(frm, (REBSER*)RXA_SERIES(frm, 3), RXA_INDEX(frm, 3), &ro, pixels);
	return Make_MPContext(frm, NULL, 0, &ro, pixels);
}

COMMAND cmd_mathpresso_compile(RXIFRM *frm, void *ctx) {
	REBHOB       *hob;
	REBSER       *code;
	MPContext    *mpc;
	MPExpression *mpe;
	Context      *mpCtx;
	Expression   *mpExp;
	MyOutputLog   outputLog;
	REBCNT        options = MPOptions;

	// Arguments: 1 = context, 2 = expression, 3 = /with, 4 = flags.
	// Flags given here replace those from `set-options` for this compilation.
	if (RXA_REF(frm, 3)) {
		i64 flags = RXA_INT64(frm, 4);
		if (flags < 0 || flags > 0xFFFF) RETURN_ERROR(ERR_BAD_OPTIONS);
		options = (REBCNT)flags;
	}

	if (RXA_TYPE(frm, 1) == RXT_STRUCT) {
		// Replaces the struct in arg 1 with a temporary MPContext handle.
		ReadOnlyList ro = { NULL, 0 };
		int result = Make_MPContext(frm, NULL, 0, &ro, false);
		if (result != RXR_VALUE) return result;
	}

	mpc = ARG_MPContext(1);
	if (mpc == NULL) return RXR_NONE;

	mpCtx = (Context*)mpc->context;
	if (mpCtx == NULL) return RXR_NONE;

	// Strings are always UTF-8 encoded byte series, terminated at the tail.
	// Compile from the string's index, like any other series argument.
	code = (REBSER*)RXA_SERIES(frm, 2);
	REBCNT index = RXA_INDEX(frm, 2);
	const char *body = index < SERIES_TAIL(code) ? (const char*)SERIES_SKIP(code, index) : "";

	// Create a new expression...
	hob = RL_MAKE_HANDLE_CONTEXT(Handle_MPExpression);
	if (hob == NULL) return RXR_NONE;
	mpe = (MPExpression*)hob->data;
	mpe->expression = mpExp = new Expression();
	mpe->struct_id = mpc->struct_id;
	mpe->bytes_needed = mpc->bytes_needed;
	mpe->read_only = mpc->read_only;
	mpe->pixels = mpc->pixels;
	debug_print("New MPExpression: %p for context: %p options: %u\n", (void*)mpExp, (void*)mpCtx, options);

	// And compile it...
	Error err = mpExp->compile(*mpCtx, body, options, &outputLog);
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
	// The expression writes into the data - unless all its variables are
	// read-only.
	if (!mpe->read_only && (info->flags & (STRUCT_FLAG_MARK | STRUCT_FLAG_PROTECTED)))
		RETURN_ERROR(ERR_RAW_STRUCT);

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
		// The expression writes into the data - unless all its variables
		// are read-only, then it may read even data it must not write.
		if (!mpe->read_only && !RXI_STRUCT_WRITABLE(&stru)) RETURN_ERROR(ERR_RAW_STRUCT);
		len = stru.size;
		bin = stru.data;
	} else {
		REBSER *ser   = RXA_VECTOR_SERIES(frm, 2);
		REBCNT  index = RXA_VECTOR_INDEX(frm, 2);
		if (RXI_VECTOR_TYPE(RXA_VECTOR_INFO(frm, 2)) != VTSF64) RETURN_ERROR(ERR_NOT_DOUBLES);
		// The index may be past the tail (the series was shortened after the
		// value was taken), and the unsigned difference would wrap around.
		len = index < SERIES_TAIL(ser) ? (REBU64)(SERIES_TAIL(ser) - index) * sizeof(REBDEC) : 0;
		bin = SERIES_SKIP(ser, index);
	}
	if (len < mpe->bytes_needed) {
		debug_print("Data bytes: %llu, needed: %u\n", (unsigned long long)len, mpe->bytes_needed);
		RETURN_ERROR(ERR_SHORT_DATA);
	}

	RETURN_DOUBLE(((Expression*)mpe->expression)->evaluate(bin));
}

// none clears the options. Returns false (and keeps the current options)
// for flags out of range.
COMMAND cmd_mathpresso_set_options(RXIFRM *frm, void *ctx) {
	REBU64 num;
	// The argument slot of none holds no number - it must not be read as one.
	if (RXA_TYPE(frm, 1) == RXT_NONE) {
		MPOptions = 0;
		return RXR_TRUE;
	}
	num = RXA_UINT64(frm, 1);
	if (num > 0xFFFFu) return RXR_FALSE;
	MPOptions = (REBCNT)num;
	return RXR_TRUE;
}

// A colour channel: rounded and clamped to 0..255 (NaN gives 0).
static inline REBYTE Channel(double v) {
	if (!(v > 0.0)) return 0;
	if (v >= 255.0) return 255;
	return (REBYTE)(v + 0.5);
}

// render: evaluates the expression once per pixel of the image, from the
// image's index to its end. The struct's bytes are copied once into a
// buffer, followed by the pixel variables; per pixel, x and y are set,
// r g b to 0 and a to 255, and after the evaluation the colour is written.
// The struct itself is never written, so any struct of the spec is accepted.
//
// With /with, `buf` is read from the vector (one double per pixel, from the
// vector's index) before the evaluation and written back after it - a value
// kept for every pixel from one call to the next. Without it, `buf` is 0.
//
// Arguments: 1 = expression, 2 = data, 3 = image, 4 = /with, 5 = buffer.
COMMAND cmd_mathpresso_render(RXIFRM *frm, void *ctx) {
	MPExpression *mpe;
	RXISTRU  stru;
	REBYTE  *mem, *pix;
	double  *var, *vals = NULL;
	REBCNT   width, start, count, n, col, row;
	REBYTE   local[512];

	mpe = ARG_MPExpression(1);
	if (mpe == NULL || mpe->expression == NULL) RETURN_ERROR(ERR_NO_EXPRESSION);
	if (mpe->pixels == NO_PIXELS) RETURN_ERROR(ERR_NO_PIXELS);

	if (!RXA_STRUCT_INFO(frm, 2, &stru)) RETURN_ERROR(ERR_BAD_STRUCT);
	if (mpe->struct_id != stru.id)        RETURN_ERROR(ERR_STRUCT_ID);
	// The same spec, so the same size - but never copy past the gap.
	if (stru.size > mpe->pixels)          RETURN_ERROR(ERR_STRUCT_ID);

	width = (REBCNT)RXA_IMAGE_WIDTH(frm, 3);
	start = RXA_IMAGE_INDEX(frm, 3);
	count = width ? RXA_IMAGE_LEN(frm, 3) : 0;

	if (RXA_REF(frm, 4)) {
		REBSER *ser   = RXA_VECTOR_SERIES(frm, 5);
		REBCNT  index = RXA_VECTOR_INDEX(frm, 5);
		REBCNT  tail  = SERIES_TAIL(ser);
		if (RXI_VECTOR_TYPE(RXA_VECTOR_INFO(frm, 5)) != VTSF64) RETURN_ERROR(ERR_SHORT_BUFFER);
		// The index may be past the tail (the vector was shortened since).
		if (index > tail || tail - index < count)               RETURN_ERROR(ERR_SHORT_BUFFER);
		vals = (double*)SERIES_SKIP(ser, index);
	}

	mem = mpe->bytes_needed <= sizeof(local) ? local : (REBYTE*)malloc(mpe->bytes_needed);
	if (mem == NULL) RETURN_ERROR("Out of memory!");
	memset(mem, 0, mpe->bytes_needed);
	memcpy(mem, stru.data, stru.size);
	var = (double*)(mem + mpe->pixels);   // x y r g b a buf

	// Not RXA_IMAGE_DATA: its RL_SERIES call passes the image as a void*,
	// which C++ does not convert to REBSER* implicitly.
	pix   = (REBYTE*)RL_SERIES((REBSER*)RXA_IMAGE(frm, 3), RXI_SER_DATA) + (REBUPT)start * 4;
	col   = width ? start % width : 0;
	row   = width ? start / width : 0;

	Expression *e = (Expression*)mpe->expression;
	for (n = 0; n < count; n++, pix += 4) {
		var[0] = (double)col;
		var[1] = (double)row;
		var[2] = var[3] = var[4] = 0.0;
		var[5] = 255.0;
		var[6] = vals ? vals[n] : 0.0;
		e->evaluate(mem);
		pix[C_R] = Channel(var[2]);
		pix[C_G] = Channel(var[3]);
		pix[C_B] = Channel(var[4]);
		pix[C_A] = Channel(var[5]);
		if (vals) vals[n] = var[6];
		if (++col == width) { col = 0; row++; }
	}
	if (mem != local) free(mem);

	// The image (at its index) is the result.
	RXA_ARG(frm, 1)  = RXA_ARG(frm, 3);
	RXA_TYPE(frm, 1) = RXT_IMAGE;
	return RXR_VALUE;
}
