//
// auto-generated file, do not modify!
//

#include "mathpresso-command.h"

#define MIN_REBOL_VER 3
#define MIN_REBOL_REV 10
#define MIN_REBOL_UPD 2
#define VERSION(a, b, c) (a << 16) + (b << 8) + c
#define MIN_REBOL_VERSION VERSION(MIN_REBOL_VER, MIN_REBOL_REV, MIN_REBOL_UPD)

enum ext_commands {
	CMD_MATH_CONTEXT,
	CMD_MATH_COMPILE,
	CMD_MATH_EVAL,
};


int cmd_context(RXIFRM *frm, void *ctx);
int cmd_compile(RXIFRM *frm, void *ctx);
int cmd_eval(RXIFRM *frm, void *ctx);
enum math_cmd_words {W_MATH_CMD_0
};
enum math_arg_words {W_MATH_ARG_0
};

typedef int (*MyCommandPointer)(RXIFRM *frm, void *ctx);

#define MATH_EXT_INIT_CODE \
	"REBOL [Title: \"Rebol Mathpresso Extension\" Name: mathpresso Type: module Version: 0.1.0 Author: Oldes Date: 3-Feb-2023/17:21:32 License: Apache-2.0 Url: https://github.com/Siskin-framework/Rebol-Mathpresso]\n"\
	"context: command [{Initialize MPContext handle with given variable names} spec [block!] \"Block of variable names used by expressions\"]\n"\
	"compile: command [\"Compile math expression using the given context\" context [handle!] \"MPContext\" expression [string!] \"Math expression\"]\n"\
	"eval: command [{Evaluate precompiled math expressions using given variables} expression [handle!] \"MPExpression\" variables [vector!] \"Variables in a double format\"]protect/hide 'words\n"\
	"\n"
