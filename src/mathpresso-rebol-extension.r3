REBOL [
	title: "Mathpresso module builder"
	type: module
]

commands: [
;	init-words: [cmd-words [block!] arg-words [block!]]
;	;--------------------------
	context: [
		"Initialize MPContext handle with given variable names"
		spec [block!] "Block of variable names used by expressions"
	]
	compile: [
		"Compile math expression using the given context"
		context [handle!] "MPContext"
		expression [string!] "Math expression"
	]
	eval: [
		"Evaluate precompiled math expressions using given variables"
		expression [handle!] "MPExpression"
		variables  [vector!] "Variables in a double format"
	]
]

cmd-words: []
arg-words: []


;-------------------------------------- ----------------------------------------
reb-code: ajoin [
	{REBOL [Title: "Rebol Mathpresso Extension"}
	{ Name: mathpresso Type: module}
	{ Version: 0.1.0}
	{ Author: Oldes}
	{ Date: } now/utc
	{ License: Apache-2.0}
	{ Url: https://github.com/Siskin-framework/Rebol-Mathpresso}
	#"]"
]
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
append reb-code "protect/hide 'words^/"

print reb-code

;- convert Rebol code to C-string ----------------------------------------------
init-code: copy ""
foreach line split reb-code lf [
	replace/all line #"^"" {\"}
	append init-code ajoin [{\^/^-"} line {\n"}] 
]

;-- C file templates -----------------------------------------------------------
header: {//
// auto-generated file, do not modify!
//

#include "mathpresso-command.h"

#define MIN_REBOL_VER 3
#define MIN_REBOL_REV 10
#define MIN_REBOL_UPD 2
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
ctable: {//
// auto-generated file, do not modify!
//
#include "mathpresso-rebol-extension.h"
MyCommandPointer Command[] = {
$cmd-dispatch};
}

;- output generated files ------------------------------------------------------
write %mathpresso-rebol-extension.h reword :header self
write %mathpresso-commands-table.c  reword :ctable self
