//
// MathPresso experimental Rebol extension
// =======================================
// Use on your own risc!

#include "mathpresso.h"
extern "C" {
	#include "mathpresso-rebol-extension.h"
}

#include <stdio.h>
#include <stdlib.h>

extern REBCNT Handle_MPExpression;
extern REBCNT Handle_MPContext;

#define COMMAND extern "C" int

#define FRM_IS_HANDLE(n, t)     (RXA_TYPE(frm,n) == RXT_HANDLE && RXA_HANDLE_TYPE(frm, n) == t)
#define ARG_Is_MPContext(n)     FRM_IS_HANDLE(n, Handle_MPContext)
#define ARG_Is_MPExpression(n)  FRM_IS_HANDLE(n, Handle_MPExpression)
#define ARG_MPContext(n)        (ARG_Is_MPContext(n)    ? (MPContext*)   (RXA_HANDLE_CONTEXT(frm, n)->handle) : NULL)
#define ARG_MPExpression(n)     (ARG_Is_MPExpression(n) ? (MPExpression*)(RXA_HANDLE_CONTEXT(frm, n)->handle) : NULL)
#define ARG_Series(n)           (REBSER *)RXA_SERIES(frm, n)
#define ARG_Index(n)            RXA_INDEX(frm, n)

static char* err_buff[255]; // temporary buffer used to pass an exception messages to Rebol side
#define RETURN_ERROR(err) \
	snprintf((char*)err_buff, 254,"%s", err);\
	RXA_SERIES(frm, 1) = (void*)err_buff;\
	return RXR_ERROR

#define RETURN_HANDLE(hob)                 \
	RXA_HANDLE(frm, 1)       = hob;        \
	RXA_HANDLE_TYPE(frm, 1)  = hob->sym;   \
	RXA_HANDLE_FLAGS(frm, 1) = hob->flags; \
	RXA_TYPE(frm, 1) = RXT_HANDLE;         \
	return RXR_VALUE

#define RETURN_DOUBLE(d)                   \
	RXA_TYPE(frm, 1) = RXT_DECIMAL;        \
	RXA_DEC64(frm, 1) = (d);               \
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

#define  MAX_VERBOSE_FLAGS (kOptionVerbose | kOptionDebugAst | kOptionDebugMachineCode | kOptionDebugCompiler)
#define  AST_VERBOSE_FLAGS (kOptionVerbose | kOptionDebugAst)
#define CODE_VERBOSE_FLAGS (kOptionVerbose | kOptionDebugMachineCode)

extern "C" {
	void* releaseMPExpression(void* hndl) {
		if (hndl != NULL) {
			MPExpression *exp = (MPExpression*)hndl;
			if(exp->expression) {
				debug_print("GC MPExpression %p, variables: %u\n", exp->expression, exp->variables);
				delete (mathpresso::Expression*)exp->expression;
			}
		}
		return NULL;
	}
	void* releaseMPContext(void* hndl) {
		if (hndl != NULL) {
			MPContext *mpc = (MPContext *)hndl;
			if(mpc->context) { 
				debug_print("GC MPContext %p, variables: %u\n", mpc->context, mpc->variables);
				delete (mathpresso::Context*)mpc->context;
			}
		}
		return NULL;
	}
}

COMMAND cmd_context(RXIFRM *frm, void *rctx) {
	REBSER *blk;
	RXIARG val;
	REBCNT index;
	REBINT type;

	blk = (REBSER *)RXA_SERIES(frm, 1);
	index = RXA_INDEX(frm, 1);

	REBHOB* hob = RL_MAKE_HANDLE_CONTEXT(Handle_MPContext);
	if (hob == NULL) return RXR_NONE;

	MPContext *mpc = (MPContext*)hob->data;
	mathpresso::Context *c = new mathpresso::Context();
	mpc->context   = c;
	mpc->variables = 0;

	debug_print("New MPContext: %p\n", c);

	c->addBuiltIns();

	while (index < blk->tail) {
		type = RL_GET_VALUE(blk, index, &val);
		if (type == RXT_WORD) {
			debug_print("word: %s\n", RL_WORD_STRING(val.int32a));
			c->addVariable(cs_cast(RL_WORD_STRING(val.int32a)), mpc->variables*sizeof(REBDEC));
			mpc->variables++;
		}
		else {
			debug_print("ignoring type: %i\n", type);
			//RXA_SERIES(frm, 1) = "Unsupported argument!";
			//RL_FREE_HANDLE_CONTEXT(hob);
			//return RXR_NONE;
		}
		index++;
	}
	RETURN_HANDLE(hob);
}

COMMAND cmd_compile(RXIFRM *frm, void *ctx) {	
	REBDEC result = 0;
	MyOutputLog outputLog;

	MPContext *mpc = ARG_MPContext(1);
	REBSER    *src = ARG_Series(2);

	if(!mpc) return RXR_FALSE; // invalid context handle

	REBHOB* hob = RL_MAKE_HANDLE_CONTEXT(Handle_MPExpression);
	if (hob == NULL) return RXR_NONE;

	MPExpression *mpe = (MPExpression*)hob->data;
	Expression *e = new mathpresso::Expression();
	Context *c = (Context*)mpc->context;

	mpe->expression = e;
	mpe->variables  = mpc->variables;
	
	debug_print("New MPExpression: %p for context: %p with %u variables.\n", e, c, mpe->variables);

	if(SERIES_WIDE(src) > 1)
		src = RL_ENCODE_UTF8_STRING(SERIES_DATA(src), SERIES_TAIL(src), SERIES_WIDE(src) > 1, FALSE);

	Error err = e->compile(*c, SERIES_TEXT(src), kOptionVerbose, &outputLog);
	if (err != kErrorOk) {
		RL_FREE_HANDLE_CONTEXT(hob);
		return RXR_NONE;
	}
	RETURN_HANDLE(hob);
}

COMMAND cmd_eval(RXIFRM *frm, void *ctx) {
	MPExpression *mpe;
	REBSER *vec;
	REBU64 bytesNeeded, vecBytes;

	mpe = ARG_MPExpression(1);
	vec = ARG_Series(2);

	if(mpe == NULL) {
		RETURN_ERROR("Command needs a valid MPExpression handle!");
	}
	if(VECT_TYPE(vec) != 11) {
		RETURN_ERROR("Command needs a vector with double values!");
	}
	
	vecBytes = (SERIES_TAIL(vec) - ARG_Index(2)) * sizeof(REBDEC);
	bytesNeeded = mpe->variables * sizeof(REBDEC);
	if(vecBytes < bytesNeeded) {
		debug_print("Vector bytes: %llu, needed: %llu\n", vecBytes, bytesNeeded);
		RETURN_ERROR("Insufficient size of input data!");
	}

	Expression *e = (Expression*)mpe->expression;

	RETURN_DOUBLE(e->evaluate(SERIES_SKIP(vec, ARG_Index(2))));
}
