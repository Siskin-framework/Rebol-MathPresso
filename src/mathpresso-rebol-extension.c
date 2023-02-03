//
// Mathpresso experimental Rebol extension
// ====================================
// Use on your own risc!

#include "mathpresso-rebol-extension.h"

RL_LIB *RL; // Link back to reb-lib from embedded extensions

//==== Globals ===============================================================//
REBCNT* math_cmd_words;
REBCNT* math_arg_words;
REBCNT  Handle_MPExpression;
REBCNT  Handle_MPContext;

extern MyCommandPointer Command[];          // in mathpresso-commands-table.c //
//============================================================================//

extern void* releaseMPExpression(void* hndl);
extern void* releaseMPContext(void* hndl);

static const char* init_block = MATH_EXT_INIT_CODE;

int cmd_init_words(RXIFRM *frm, void *ctx) {
	math_cmd_words = RL_MAP_WORDS(RXA_SERIES(frm,1));
	math_arg_words = RL_MAP_WORDS(RXA_SERIES(frm,2));
	return RXR_TRUE;
}

RXIEXT const char *RX_Init(int opts, RL_LIB *lib) {
    RL = lib;
	REBYTE ver[8];
	RL_VERSION(ver);
	debug_print("RXinit MathPresso; Rebol v%i.%i.%i\n", ver[1], ver[2], ver[3]);

	if (MIN_REBOL_VERSION > VERSION(ver[1], ver[2], ver[3])) {
		debug_print("Needs at least Rebol v%i.%i.%i!\n", MIN_REBOL_VER, MIN_REBOL_REV, MIN_REBOL_UPD);
		return 0;
	}
    if (!CHECK_STRUCT_ALIGN) {
    	trace("CHECK_STRUCT_ALIGN failed!");
    	return 0;
    }
	Handle_MPExpression = RL_REGISTER_HANDLE(b_cast("MPExpression"), sizeof(MPExpression), releaseMPExpression);
	Handle_MPContext    = RL_REGISTER_HANDLE(b_cast("MPContext"),    sizeof(MPContext),    releaseMPContext);
    return init_block;
}

RXIEXT int RX_Call(int cmd, RXIFRM *frm, void *ctx) {
	return Command[cmd](frm, ctx);
}

RXIEXT int RX_Quit(int opts) {
    return 0;
}
