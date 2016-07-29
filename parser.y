/*
	Copyright(C) 2016, Red Hat, Inc., Jerome Marchand

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

%{
#include "parser.h"
#include <limits.h>

#define abort(...)				\
{						\
	fprintf(stderr, __VA_ARGS__);		\
	YYABORT;				\
}

%}

%union {
	int i;
	unsigned int ui;
	long l;
	unsigned long ul;
	void *ptr;
	char *str;
	obj_t *obj;
	obj_list_head_t *list;
}

%token <str> IDENTIFIER STRING SRCFILE
%token <l> CONSTANT

%token NEWLINE
%token TYPEDEF
%token CONST VOLATILE
%token STRUCT UNION ENUM ELLIPSIS

%type <str> type_qualifier
%type <obj> typed_type base_type reference_file array_type
%type <obj> type ptr_type variable_var_list func_type elt enum_elt enum_type
%type <obj> union_type struct_type struct_elt
%type <obj> declaration_var declaration_typedef declaration kabi_dw_file
%type <list> elt_list arg_list enum_list struct_list

%parse-param {obj_t **root}

%%

kabi_dw_file:
	cu_file NEWLINE source_file NEWLINE declaration NEWLINE
	{
	    $$ = *root = $declaration;
	}
	;

cu_file:
	IDENTIFIER STRING
	{
	    if (strcmp($IDENTIFIER,"CU"))
		abort("Wrong CU keyword: \"%s\"\n", $IDENTIFIER);
	    free($IDENTIFIER);
	    free($STRING);
	}
	;

source_file:
	IDENTIFIER SRCFILE ':' CONSTANT
	{
	    if (strcmp($IDENTIFIER,"File"))
		abort("Wrong file keyword: \"%s\"\n", $IDENTIFIER);
	    free($IDENTIFIER);
	    free($SRCFILE);
	}
	;

/* Possible types are struct union enum func typedef and var */
declaration:
	struct_type
	| union_type
	| enum_type
	| func_type
	| declaration_typedef
	| declaration_var
	;

declaration_typedef:
	TYPEDEF IDENTIFIER NEWLINE type
	{
	    $$ = new_typedef_add($IDENTIFIER, $type);
	}
	;

declaration_var:
	IDENTIFIER IDENTIFIER type
	{
	    if (strcmp($1,"var"))
		abort("Wrong var keyword: \"%s\"\n", $1);
	    free($1);
	    $$ = new_var_add($2, $type);
	}
	;

type:
	base_type
	| reference_file
	| struct_type
	| union_type
	| enum_type
	| func_type
	| ptr_type
	| array_type
	| typed_type
	;

struct_type:
	STRUCT IDENTIFIER '{' NEWLINE '}'
	{
	    $$ = new_struct($IDENTIFIER);
	}
	| STRUCT IDENTIFIER '{' NEWLINE struct_list NEWLINE '}'
	{
	    $$ = new_struct($IDENTIFIER);
	    $$->member_list = $struct_list;
	}
	;

struct_list:
	struct_elt
	{
	    $$ = new_list_head($struct_elt);
	}
	| struct_list NEWLINE struct_elt
	{
	    list_add($1, $struct_elt);
	    $$ = $1;
	}
	;

struct_elt:
	CONSTANT IDENTIFIER type
	{
	    $$ = new_struct_member_add($IDENTIFIER, $type);
	    $$->offset = $CONSTANT;
	}
	| CONSTANT ':' CONSTANT '-' CONSTANT IDENTIFIER type
	{
	    if ($5 > UCHAR_MAX || $3 > $5)
		abort("Invalid offset: %lx:%lu:%lu\n", $1, $3, $5);
	    $$ = new_struct_member_add($IDENTIFIER, $type);
	    $$->offset = $1;
	    $$->first_bit = $3;
	    $$->last_bit = $5;
	}
	;

union_type:
	UNION IDENTIFIER '{' NEWLINE '}'
	{
	    $$ = new_union($IDENTIFIER);
	}
	| UNION IDENTIFIER '{' NEWLINE elt_list NEWLINE '}'
	{
	    $$ = new_union($IDENTIFIER);
	    $$->member_list = $elt_list;
	}
	;

enum_type:
	ENUM IDENTIFIER '{' NEWLINE enum_list NEWLINE '}'
	{
	    $$ = new_enum($IDENTIFIER);
	    $$->member_list = $enum_list;
	}
	;

enum_list:
	enum_elt
	{
	    $$ = new_list_head($enum_elt);
	}
	| enum_list NEWLINE enum_elt
	{
	    list_add($1, $enum_elt);
	    $$ = $1;
	}
	;

enum_elt:
	IDENTIFIER '=' CONSTANT
	{
	    $$ = new_constant($IDENTIFIER);
	    $$->constant = $CONSTANT;
	}
	;

func_type:
	IDENTIFIER IDENTIFIER '(' NEWLINE arg_list ')' NEWLINE type
	{
	    if (strcmp($1,"func"))
		abort("Wrong func keyword: \"%s\"\n", $1);
	    free($1);
	    $$ = new_func_add($2, $type);
	    $$->member_list = $arg_list;
	}
	| IDENTIFIER reference_file /* protype define as typedef */
	{
	    if (strcmp($IDENTIFIER,"func"))
		abort("Wrong func keyword: \"%s\"\n", $IDENTIFIER);
	    free($IDENTIFIER);
	    /* TODO: Need to parse other file */
	    $$ = new_func_add(NULL, $reference_file);
	}
	;

arg_list:
	%empty
	{
	    /* TODO: that's ugly. Is it correct? */
	    $$ = NULL;
	}
	| elt_list NEWLINE
	{
	    $$ = $elt_list;
	}
	| variable_var_list NEWLINE
	{
	    $$ = new_list_head($variable_var_list);
	}
	| elt_list NEWLINE variable_var_list NEWLINE
	{
	    list_add($elt_list, $variable_var_list);
	    $$ = $elt_list;
	}
	;

variable_var_list:
	IDENTIFIER ELLIPSIS
	{
	    /* TODO: there may be a better solution */
	    $$ = new_base(strdup("..."));
	}
	;

elt_list:
	elt
	{
	    $$ = new_list_head($elt);
	}
	| elt_list NEWLINE elt
	{
	    list_add($1, $elt);
	    $$ = $1;
	}
	;

elt:
	IDENTIFIER type
	{
	    $$ = new_var_add($IDENTIFIER, $type);
	}
	;

ptr_type:
	'*' type
	{
	    $$ = new_ptr_add($type);
	}
	;

array_type:
	'[' CONSTANT ']' STRING
	{
	    $$ = new_array();
	    $$->index = $CONSTANT;
	    $$->base_type = $STRING;
	}
	| '[' CONSTANT ']' array_type
	{
	    $$ = new_array_add($4);
	    $$->index = $CONSTANT;
	}
	;

typed_type:
	type_qualifier type
	{
	    $$ = new_qualifier_add($type);
	    $$->base_type = $type_qualifier;
	}
	;

type_qualifier:
	CONST
	{
	    debug("Qualifier: const\n");
	    $$ = strdup("const");
	}
	| VOLATILE
	{
	    debug("Qualifier: volatile\n");
	    $$ = strdup("volatile");
	}
	;

base_type:
	STRING
	{
	    debug("Base type: %s\n", $STRING);
	    $$ = new_base($STRING);
	}
	;

reference_file:
	'@' STRING
	{
	    /* TODO: need to parse that file */
	    $$ = new_none();
	    $$->base_type = $STRING;
	    }
	;

%%

extern void usage(void);

int parse(int argc, char **argv)
{
	int ret;
	char *filename;
	FILE *kabi_file;
	obj_t *root;

#ifdef DEBUG
	yydebug = 1;
#else
	yydebug = 0;
#endif

	if (argc != 1) {
		usage();
	}
	filename = argv[0];
	kabi_file = fopen(filename, "r");
	if (kabi_file == NULL) {
		fprintf(stderr, "Failed to open kABI file: %s\n",
			filename);
		return 1;
	}

	yyin = kabi_file;
	ret = yyparse(&root);
	if (ret)
	    return ret;

	if (!root) {
		fprintf(stderr, "No root\n");
		exit(1);
	}
	print_tree(root);
	if (yydebug)
	    debug_tree(root);
	free_obj(root);

	return 0;
}

int yyerror(obj_t **root, char *s)
{
	fprintf(stderr, "error: %s\n", s);
	return 0;
}
