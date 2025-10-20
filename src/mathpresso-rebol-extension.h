//   ____  __   __        ______        __
//  / __ \/ /__/ /__ ___ /_  __/__ ____/ /
// / /_/ / / _  / -_|_-<_ / / / -_) __/ _ \
// \____/_/\_,_/\__/___(@)_/  \__/\__/_// /
//  ~~~ oldes.huhuman at gmail.com ~~~ /_/
//
// Project: Rebol/MiniAudio extension
// SPDX-License-Identifier: MIT
// =============================================================================
// NOTE: auto-generated file, do not modify!


#include "mathpresso-command.h"

#define MIN_REBOL_VER 3
#define MIN_REBOL_REV 19
#define MIN_REBOL_UPD 1
#define VERSION(a, b, c) (a << 16) + (b << 8) + c
#define MIN_REBOL_VERSION VERSION(MIN_REBOL_VER, MIN_REBOL_REV, MIN_REBOL_UPD)

enum ext_commands {
	CMD_MATH_CONTEXT,
	CMD_MATH_COMPILE,
	CMD_MATH_EVAL,
	CMD_MATH_SET_OPTIONS,
};


int cmd_context(RXIFRM *frm, void *ctx);
int cmd_compile(RXIFRM *frm, void *ctx);
int cmd_eval(RXIFRM *frm, void *ctx);
int cmd_set_options(RXIFRM *frm, void *ctx);
enum math_cmd_words {W_MATH_CMD_0
};
enum math_arg_words {W_MATH_ARG_0
};

typedef int (*MyCommandPointer)(RXIFRM *frm, void *ctx);

#define MATH_EXT_INIT_CODE \
	"REBOL [Title: \"Rebol Mathpresso Extension\" Name: mathpresso Type: module Version: 0.2.0 Author: Oldes Date: 15-May-2025/11:22:19 License: MIT Url: https://github.com/Siskin-framework/Rebol-Mathpresso]\n"\
	"context: command [{Initialize MPContext handle with given variable names} spec [struct!] {Struct with double fields used as expression variables}]\n"\
	"compile: command [\"Compile math expression using the given context\" context [struct! handle!] {Struct with double fields used by expression as variables or existing MPContext handle} expression [string!] \"Math expression\" /with flags [integer!] \"Optional compilation flags\"]\n"\
	"eval: command [{Evaluate precompiled math expressions using given variables} expression [handle!] \"MPExpression\" variables [vector! struct!] \"Variables in a double format\"]\n"\
	"set-options: command [{MathPresso options used when expression is being compiled} flags [integer! none!] {Combination of: 1 = Verbose, 2 = DebugAst, 4 = DebugMachineCode, 8 = DebugCompiler}]\n"\
	";- Options used with the `set-options` command.\n"\
	"kOptionVerbose:          1 ;; Show messages and warnings.\n"\
	"kOptionDebugAst:         2 ;; Debug AST (shows initial and final AST).\n"\
	"kOptionDebugMachineCode: 4 ;; Debug machine code generated.\n"\
	"kOptionDebugCompiler:    8 ;; Debug AsmJit's compiler.\n"\
	"\n"
