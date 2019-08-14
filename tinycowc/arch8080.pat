#include "globals.h"
#include "midcode.h"
#include "emitter.h"
#include "regalloc.h"

struct subarch
{
    int id;
};

static int id = 1;

enum
{
    REG_A = 1<<0,
    REG_B = 1<<1,
    REG_D = 1<<2,
    REG_H = 1<<3,
    REG_BC = 1<<4,
    REG_DE = 1<<5,
    REG_HL = 1<<6,

    REG_16 = REG_BC | REG_DE | REG_HL,
    REG_8 = REG_A | REG_B | REG_D | REG_H
};

#define E emitter_printf

void arch_init_types(void)
{
	intptr_type = make_number_type("uint16", 2, false);
	make_number_type("int16", 2, true);
	uint8_type = make_number_type("uint8", 1, false);
	make_number_type("int8", 1, true);

    regalloc_add_register("a", REG_A, REG_A);
    regalloc_add_register("b", REG_B, REG_B | REG_BC);
    regalloc_add_register("d", REG_D, REG_D | REG_DE);
    regalloc_add_register("h", REG_H, REG_H | REG_HL);
    regalloc_add_register("bc", REG_BC, REG_B | REG_BC);
    regalloc_add_register("de", REG_DE, REG_D | REG_DE);
    regalloc_add_register("hl", REG_HL, REG_H | REG_HL);
}

void arch_init_subroutine(struct subroutine* sub)
{
    sub->arch = calloc(1, sizeof(struct subarch));
    sub->arch->id = id++;
}

void arch_init_variable(struct symbol* var)
{
}

void arch_emit_comment(const char* text, ...)
{
    va_list ap;
    va_start(ap, text);
    printf("\t; ");
    vprintf(text, ap);
    printf("\n");
    va_end(ap);
}

static const char* symref(struct symbol* sym, int32_t off)
{
    static char buffer[32];
    snprintf(buffer, sizeof(buffer), "w%d%+d",
        sym->u.var.sub->arch->id,
        sym->u.var.offset + off);
    return buffer;
}

static const char* labelref(int label)
{
    static char buffer[32];
    snprintf(buffer, sizeof(buffer), "X%d", label);
    return buffer;
}

void arch_load_const(reg_t id, int32_t num)
{
    if (id & REG_16)
        E("\tlxi %s, %d\n", regname(id), num & 0xffff);
    else
        E("\tmvi %s, %d\n", regname(id), num & 0xff);
}

void arch_load_var(reg_t id, struct symbol* sym, int32_t off)
{
    assert(id & (REG_HL|REG_A));
    if (id & REG_HL)
        E("\tlhld %s\n", symref(sym, off));
    else
        E("\tlda %s\n", symref(sym, off));
}

void arch_push(reg_t id)
{
    E("\tpush %s\n", regname(id));
}

void arch_pop(reg_t id)
{
    E("\tpop %s\n", regname(id));
}

void arch_copy(reg_t src, reg_t dest)
{
    E("\tcopy %s -> %s\n", regname(src), regname(dest));
}
%%

i1
i2
constant(int32_t val) = ("%d", $$.val)
const1(int32_t val) = ("%d", $$.val)
const2(int32_t val) = ("%d", $$.val)
address(struct symbol* sym, int32_t off) = ("%s+%d", $$.sym->name, $$.off)

%%

STARTFILE --

ENDFILE --

STARTSUB(sub) --
    emitter_open_chunk();
    E("\n");
    E("; %s\n", sub->name);
    E("f%d:\n", sub->arch->id);

ENDSUB(sub) --
    E("\tret\n");
	E("w%d: ds %d\n", sub->arch->id, sub->workspace);
    emitter_close_chunk();

JUMP(label) --
    regalloc_reg_changing(ALL_REGS);
    E("\tjmp %s\n", labelref(label));

JUMP(target) LABEL(label1) LABEL(label2) -- LABEL(label1) LABEL(label2)
    regalloc_reg_changing(ALL_REGS);
    if ((target != label1) && (target != label2))
        E("\tjmp %s\n", labelref(target));

LABEL(label) --
    regalloc_reg_changing(ALL_REGS);
    E("%s:\n", labelref(label));

LABELALIAS(newlabel, oldlabel) --
    E("%s\t", labelref(newlabel));
    E("= %s\n", labelref(oldlabel));

CONSTANT(val) -- constant(val)

ADDRESS(sym) -- address(sym, 0)

constant(lhs) constant(rhs) ADD(n) -- constant(result)
    result = lhs + rhs;

i1 i1 ADD(1) -- i1
    reg_t rhs = regalloc_pop(REG_8 & ~REG_A);
    reg_t lhs = regalloc_pop(REG_A);
    E("\tadd %s\n", regname(lhs));
    regalloc_push(REG_A);

i1 const1(n) ADD(1) -- i1
    if (n == 1)
    {
        reg_t val = regalloc_pop(REG_8);
        E("\tinc %s\n", regname(val));
        regalloc_push(val);
    }
    else if (n == -1)
    {
        reg_t val = regalloc_pop(REG_8);
        E("\tdec %s\n", regname(val));
        regalloc_push(val);
    }
    else
    {
        reg_t lhs = regalloc_pop(REG_A);
        E("\tadi %d\n", n & 0xff);
        regalloc_push(REG_A);
    }

i2 i2 ADD(2) -- i2
    reg_t rhs = regalloc_pop(REG_16 & ~REG_HL);
    reg_t lhs = regalloc_pop(REG_HL);
    E("\tdad %s\n", regname(lhs));
    regalloc_push(REG_HL);

i2 const2(n) ADD(2) -- i2
    if (n == 1)
    {
        reg_t val = regalloc_pop(REG_16);
        E("\tinx %s\n", regname(val));
        regalloc_push(val);
    }
    else if (n == -1)
    {
        reg_t val = regalloc_pop(REG_16);
        E("\tdex %s\n", regname(val));
        regalloc_push(val);
    }
    else
    {
        reg_t lhs = regalloc_pop(REG_HL);
        reg_t rhs = regalloc_load_const(REG_16, n);
        E("\tdad %s\n", regname(lhs));
        regalloc_push(REG_HL);
    }

ADDRESS(sym) -- address(sym, 0)

CONSTANT(val) -- constant(val)

// --- Subtractions ---------------------------------------------------------

i1 i1 SUB(1) -- i1
    reg_t rhs = regalloc_pop(REG_8 & ~REG_A);
    reg_t lhs = regalloc_pop(REG_A);
    E("\tsub %s\n", regname(rhs));
    regalloc_push(REG_A);

SUB(2) -- NEG(2) ADD(2)

i1 const1(0) SUB(1) -- i1
i1 const1(n) SUB(1) -- i1 const1(-n) ADD(1)

i1 const2(0) SUB(2) -- i2
i2 const2(n) SUB(2) -- i2 const2(-n) ADD(2)

// --- Loads ----------------------------------------------------------------

i2 LOAD(1) -- i1
    reg_t r = regalloc_pop(REG_16);
    regalloc_alloc(REG_A);
    switch (r)
    {
        case REG_HL:
            E("\tmov a, m\n");
            break;

        case REG_BC:
            E("\tldax b\n");
            break;

        case REG_DE:
            E("\tldax d\n");
            break;
    }
    regalloc_push(REG_A);

i2 LOAD(2) -- i2
    reg_t r = regalloc_pop(REG_HL);
    regalloc_alloc(REG_A);
    E("\tmov a, m\n");
    E("\tinx h\n");
    E("\tmov h, m\n");
    E("\tmov l, a\n");
    regalloc_push(REG_HL);

address(sym, off) LOAD(1) -- i1
    regalloc_load_var(REG_A, sym, off);
    regalloc_push(REG_A);

address(sym, off) LOAD(2) -- i2
    regalloc_load_var(REG_HL, sym, off);
    regalloc_push(REG_HL);

// --- Stores ---------------------------------------------------------------

address(sym, off) i1 STORE(1) --
    regalloc_var_changing(sym, off);
    regalloc_pop(REG_A);
    E("\tsta %s\n", symref(sym, off));
    regalloc_reg_contains_var(REG_A, sym, off);

address(sym, off) i2 STORE(2) --
    regalloc_var_changing(sym, off);
    regalloc_pop(REG_HL);
    E("\tshld %s\n", symref(sym, off));
    regalloc_reg_contains_var(REG_HL, sym, off);

i2 i1 STORE(1) --
    regalloc_pop(REG_A);
    reg_t r = regalloc_pop(REG_16);
    switch (r)
    {
        case REG_HL:
            E("\tmov m, a\n");
            break;

        case REG_BC:
            E("\tstax b\n");
            break;

        case REG_DE:
            E("\tstax d\n");
            break;
    }

i2 i2 STORE(2) --
    reg_t r = regalloc_pop(REG_DE);
    regalloc_pop(REG_HL);
    E("\tmov m, e\n");
    E("\tinx h\n");
    E("\tmov m, d\n");

// --- Branches -------------------------------------------------------------

i1 BEQZ(1, truelabel, falselabel) LABEL(nextlabel) --
    reg_t r = regalloc_pop(REG_A);
    E("\tora a\n");
    E("\tjz %s\n", labelref(truelabel));
    E("\tjmp %s\n", labelref(falselabel));

i2 BEQZ(2, truelabel, falselabel) --
    reg_t r = regalloc_pop(REG_HL);
    E("\tmov a, h\n");
    E("\tora l\n");
    E("\tjz %s\n", labelref(truelabel));
    E("\tjmp %s\n", labelref(falselabel));

BEQS(1, truelabel, falselabel) -- SUB(1) BEQZ(1, truelabel, falselabel)
BLTS(1, truelabel, falselabel) -- SUB(1) BLTZ(1, truelabel, falselabel)
BGTS(1, truelabel, falselabel) -- SUB(1) BGTZ(1, truelabel, falselabel)

BEQS(2, truelabel, falselabel) -- SUB(2) BEQZ(2, truelabel, falselabel)
BLTS(2, truelabel, falselabel) -- SUB(2) BLTZ(2, truelabel, falselabel)
BGTS(2, truelabel, falselabel) -- SUB(2) BGTZ(2, truelabel, falselabel)

// --- Constant type inference ----------------------------------------------

constant(c) STORE(1) -- const1(c) STORE(1)
constant(c) STORE(2) -- const2(c) STORE(2)

constant(c) PARAM(1) -- const1(c) PARAM(1)
constant(c) PARAM(2) -- const2(c) PARAM(2)

constant(c) NEG(1) -- const1(c) NEG(1)
constant(c) NEG(2) -- const2(c) NEG(2)

constant(c) ADD(1) -- const1(c) ADD(1)
constant(c) ADD(2) -- const2(c) ADD(2)
constant(c) (value) ADD(1) -- const1(c) (value) ADD(1)
constant(c) (value) ADD(2) -- const2(c) (value) ADD(2)

constant(c) SUB(1) -- const1(c) SUB(1)
constant(c) SUB(2) -- const2(c) SUB(2)
constant(c) (value) SUB(1) -- const1(c) (value) SUB(1)
constant(c) (value) SUB(2) -- const2(c) (value) SUB(2)

constant(c) MUL(1) -- const1(c) MUL(1)
constant(c) MUL(2) -- const2(c) MUL(2)
constant(c) (value) MUL(1) -- const1(c) (value) MUL(1)
constant(c) (value) MUL(2) -- const2(c) (value) MUL(2)

constant(c) DIVS(1) -- const1(c) DIVS(1)
constant(c) DIVS(2) -- const2(c) DIVS(2)
constant(c) (value) DIVS(1) -- const1(c) (value) DIVS(1)
constant(c) (value) DIVS(2) -- const2(c) (value) DIVS(2)

constant(c) REMS(1) -- const1(c) REMS(1)
constant(c) REMS(2) -- const2(c) REMS(2)
constant(c) (value) REMS(1) -- const1(c) (value) REMS(1)
constant(c) (value) REMS(2) -- const2(c) (value) REMS(2)

constant(c) OR(1) -- const1(c) OR(1)
constant(c) OR(2) -- const2(c) OR(2)
constant(c) (value) OR(1) -- const1(c) (value) OR(1)
constant(c) (value) OR(2) -- const2(c) (value) OR(2)

constant(c) AND(1) -- const1(c) AND(1)
constant(c) AND(2) -- const2(c) AND(2)
constant(c) (value) AND(1) -- const1(c) (value) AND(1)
constant(c) (value) AND(2) -- const2(c) (value) AND(2)

constant(c) EOR(1) -- const1(c) EOR(1)
constant(c) EOR(2) -- const2(c) EOR(2)
constant(c) (value) EOR(1) -- const1(c) (value) EOR(1)
constant(c) (value) EOR(2) -- const2(c) (value) EOR(2)

constant(c) BEQS(1, tl, fl) -- const1(c) BEQS(1, tl, fl)
constant(c) BLTS(1, tl, fl) -- const1(c) BLTS(1, tl, fl)
constant(c) BGTS(1, tl, fl) -- const1(c) BGTS(1, tl, fl)

const1(c) -- i1
    reg_t r = regalloc_load_const(REG_8, c & 0xff);
    regalloc_push(r);

const2(c) -- i2
    reg_t r = regalloc_load_const(REG_16, c & 0xffff);
    regalloc_push(r);