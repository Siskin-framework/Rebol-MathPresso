REBOL [
	Title:   "Rebol MathPresso Extension"
	Name:    mathpresso
	Version: 0.3.0
	Needs:   3.22.10
	Author:  @Oldes
	License: MIT
	Options: [delay]
	Url:     https://github.com/Siskin-framework/Rebol-MathPresso
	Exports: []
	Purpose: {
		Mathematical expression parser and JIT compiler, using Petr
		Kobalicek's MathPresso library. Expressions read and write double
		fields of a struct (or a vector of doubles).

		Data only - never evaluated. The C header (gen-mathpresso.h) and
		the command table (gen-mathpresso.c) are generated from this file
		by make-extension.r3.
	}
]

;; ---------------------------------------------------------------------------
;; Banner put on top of the generated files.
logo: {//   ____  __   __        ______        __
//  / __ \/ /__/ /__ ___ /_  __/__ ____/ /
// / /_/ / / _  / -_|_-<_ / / / -_) __/ _ \
// \____/_/\_,_/\__/___(@)_/  \__/\__/_// /
//  ~~~ oldes.huhuman at gmail.com ~~~ /_/
//
// Project: Rebol/MathPresso extension
// SPDX-License-Identifier: MIT
// =============================================================================
// NOTE: auto-generated file, do not modify!}

;; ---------------------------------------------------------------------------
;; C-side configuration
;;
;; Everything here is needed by both mathpresso.c (C) and
;; mathpresso-commands.cpp (C++). The C++ file includes the generated header
;; inside `extern "C"`, so the callbacks declared here keep C linkage there.
c-header: {
extern REBCNT Handle_MPExpression;
extern REBCNT Handle_MPContext;

typedef struct MPExpression_t {
	void* expression;  // compiled mathpresso::Expression
	u32   struct_id;
	u32   bytes_needed;
} MPExpression;

typedef struct MPContext_t {
	void* context;     // initialized mathpresso::Context
	u32   struct_id;
	u32   bytes_needed;
} MPContext;

int MPExpression_free(void *hndl);
int MPContext_free(void *hndl);
}

;; ---------------------------------------------------------------------------
;; No `handles:` block: MPContext/MPExpression are registered by hand in
;; mathpresso.c's Mathpresso_Init (size + free only). Neither has a
;; path-accessible field, so there is nothing to collect or document.

;; ---------------------------------------------------------------------------
;; Commands. Order is significant - it fixes the command indices.
;; The `_init` command is injected as the first one by the generator.
commands: [
	context: [
		"Initialize MPContext handle with given variable names"
		spec [struct!] "Struct with double fields used as expression variables (array field `v [double! [3]]` gives `v_1 v_2 v_3`)"
		/with "Add named constants (folded when an expression is compiled)"
		 constants [block!] "Name/number pairs, e.g. [gain 2.5 offset: 10]; use a ref! (@Gain) to keep the exact case"
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
		/each   "Evaluate for every struct in a vector of structs (from its index); returns the last result"
		/part
		 count [integer!] "Maximum number of elements to evaluate (with /each)"
	]
	set-options: [
		"MathPresso options used when expression is being compiled"
		flags [integer! none!] "Combination of the kOption* values; none clears them"
	]
]

;; ---------------------------------------------------------------------------
;; Module body.
mezzanine: [
	;- Options used with the `set-options` command.
	kOptionVerbose:          1 ;; Show messages and warnings.
	kOptionDebugAst:         2 ;; Debug AST (shows initial and final AST).
	kOptionDebugMachineCode: 4 ;; Debug machine code generated.
	kOptionDebugCompiler:    8 ;; Debug AsmJit's compiler.
	;- CPU features which may be excluded from the generated code (X86 only).
	;- Meant for testing the code generation - the results do not change.
	kOptionDisableSSE4_1: 4096  ;; Do not use SSE4.1 even if the CPU supports it.
	kOptionDisableAVX:    8192  ;; Do not use AVX even if the CPU supports it.
	kOptionDisableAVX512: 16384 ;; Do not use AVX-512 even if the CPU supports it.
]
