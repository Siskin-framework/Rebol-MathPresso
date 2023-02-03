//
// MathPresso experimental Rebol extension
// ====================================
// Use on your own risc!

#include <stdlib.h>
#include <math.h>
#include <stdio.h> // used also for snprintf by the info command!
#include "rebol-extension.h"

#define SERIES_TEXT(str) s_cast(SERIES_DATA(str))

#ifdef  USE_TRACES
#define debug_print(fmt, ...) do { printf(fmt, __VA_ARGS__); } while (0)
#define trace(str) puts(str)
#else
#define debug_print(fmt, ...)
#define trace(str) 
#endif

extern u32* math_cmd_words;
extern u32* math_arg_words;


typedef struct MPExpression_t {
	void* expression;  // compiled mathpresso::Expression
	u32   variables;   // number of input variables needed
} MPExpression;

typedef struct MPContext_t {
	void* context;     // initialized mathpresso::Context
	u32   variables;   // number of input variables used
} MPContext;
