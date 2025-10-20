REBOL [
	title:  "Rebol/MiniAudio module builder"
	type:    module
	date:    15-May-2025
	home:    https://github.com/Siskin-framework/Rebol-MathPresso
	version: 0.2.0
	author: @Oldes
]

commands: [
;	init-words: [cmd-words [block!] arg-words [block!]]
;	;--------------------------
	context: [
		"Initialize MPContext handle with given variable names"
		spec [struct!] "Struct with double fields used as expression variables"
	]
	compile: [
		"Compile math expression using the given context"
		context [struct! handle!] "Struct with double fields used by expression as variables or existing MPContext handle"
		expression  [string!]  "Math expression"
		/with flags [integer!] "Optional compilation flags"
	]
	eval: [
		"Evaluate precompiled math expressions using given variables"
		expression [handle!] "MPExpression"
		variables  [vector! struct!] "Variables in a double format"
	]
	set-options: [
		"MathPresso options used when expression is being compiled"
		flags [integer! none!] "Combination of: 1 = Verbose, 2 = DebugAst, 4 = DebugMachineCode, 8 = DebugCompiler"
	]
]

cmd-words: []
arg-words: []


;-------------------------------------- ----------------------------------------
reb-code: ajoin [
	{REBOL [Title: "Rebol Mathpresso Extension"}
	{ Name: mathpresso Type: module}
	{ Version: 0.2.0}
	{ Author: Oldes}
	{ Date: } now/utc
	{ License: MIT}
	{ Url: https://github.com/Siskin-framework/Rebol-Mathpresso}
	#"]"
]
logo: next {
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
}

enu-commands:  "" ;; command name enumerations
cmd-declares:  "" ;; command function declarations
cmd-dispatch:  "" ;; command functionm dispatcher
math-cmd-words: "enum math_cmd_words {W_MATH_CMD_0"
math-arg-words: "enum math_arg_words {W_MATH_ARG_0"

;- generate C and Rebol code from the command specifications -------------------
foreach [name spec] commands [
	append reb-code ajoin [lf name ": command "]
	new-line/all spec false
	append/only reb-code mold spec

	name: form name
	replace/all name #"-" #"_"
	
	append enu-commands ajoin ["^/^-CMD_MATH_" uppercase copy name #","]

	append cmd-declares ajoin ["^/int cmd_" name "(RXIFRM *frm, void *ctx);"]
	append cmd-dispatch ajoin ["^-cmd_" name ",^/"]
]

;- additional Rebol initialization code ----------------------------------------
foreach word cmd-words [
	word: uppercase form word
	replace/all word #"-" #"_"
	append math-cmd-words ajoin [",^/^-W_MATH_CMD_" word]
]
foreach word arg-words [
	word: uppercase form word
	replace/all word #"-" #"_"
	append math-arg-words ajoin [",^/^-W_MATH_ARG_" word]
]
append math-cmd-words "^/};"
append math-arg-words "^/};"
;append reb-code ajoin [{
;init-words words: } mold/flat cmd-words #" " mold/flat arg-words {
;protect/hide 'init-words}
;]
append reb-code ext-values: {
;- Options used with the `set-options` command.
kOptionVerbose:          1 ;; Show messages and warnings.
kOptionDebugAst:         2 ;; Debug AST (shows initial and final AST).
kOptionDebugMachineCode: 4 ;; Debug machine code generated.
kOptionDebugCompiler:    8 ;; Debug AsmJit's compiler.
}

print reb-code

;- convert Rebol code to C-string ----------------------------------------------
init-code: copy ""
foreach line split reb-code lf [
	replace/all line #"^"" {\"}
	append init-code ajoin [{\^/^-"} line {\n"}] 
]

;-- C file templates -----------------------------------------------------------
header: {$logo

#include "mathpresso-command.h"

#define MIN_REBOL_VER 3
#define MIN_REBOL_REV 19
#define MIN_REBOL_UPD 1
#define VERSION(a, b, c) (a << 16) + (b << 8) + c
#define MIN_REBOL_VERSION VERSION(MIN_REBOL_VER, MIN_REBOL_REV, MIN_REBOL_UPD)

enum ext_commands {$enu-commands
};

$cmd-declares
$math-cmd-words
$math-arg-words

typedef int (*MyCommandPointer)(RXIFRM *frm, void *ctx);

#define MATH_EXT_INIT_CODE $init-code
}
;;------------------------------------------------------------------------------
ctable: {$logo

#include "mathpresso-rebol-extension.h"
MyCommandPointer Command[] = {
$cmd-dispatch};
}

;- output generated files ------------------------------------------------------
write %mathpresso-rebol-extension.h reword :header self
write %mathpresso-commands-table.c  reword :ctable self


;- README documentation --------------------------------------------------------
doc: clear ""
hdr: clear ""
arg: clear ""
cmd: desc: a: t: s: readme: r: none

parse commands [
	any [
		quote init-words: skip
		|
		set cmd: set-word! into [
			(clear hdr clear arg r: none)
			(append hdr ajoin [LF LF "#### `" cmd "`"])
			set desc: opt string!
			any [
				set a word!
				set t opt block!
				set s opt string!
				(
					unless r [append hdr ajoin [" `:" a "`"]]
					append arg ajoin [LF "* `" a "`"] 
					if t [append arg ajoin [" `" mold t "`"]]
					if s [append arg ajoin [" " s]]
				)
				|
				set r refinement!
				set s opt string!
				(
					append arg ajoin [LF "* `/" r "`"] 
					if s [append arg ajoin [" " s]]
				)
			]
			(
				append doc hdr
				append doc LF
				append doc any [desc ""]
				append doc arg
			)
		]
	]
]


try/with [
	readme: read/string %../README.md
	readme: clear find/tail readme "## Extension commands:"
	append readme ajoin [
		LF doc
		LF LF
		LF "## Other extension values:"
		LF "```rebol"
		trim/tail ext-values
		LF "```"
		LF
	]
	write %../README.md head readme
] :print

