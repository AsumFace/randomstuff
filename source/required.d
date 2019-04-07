module required;

version(LDC)
{
    import ldc.intrinsics;
    private pragma(LDC_inline_ir) R inlineIR(string s, R, P...)(P) @nogc pure nothrow;

    void require(bool cond, const(char)[] a...) @nogc pure nothrow
    {
        if (!cond)
        {
            version(assert)
                assert(0, a);
            else
                auto _ = inlineIR!("unreachable", int)(0);
        }
    }
}
else version(GNU)
{
    import gcc.builtins;
    void require(bool cond, const(char)[] a...) @nogc pure nothrow
    {
        if (!cond)
        {
            version(assert)
                assert(0, a);
            else
                __builtin_unreachable;
        }
    }
}
else
{
    void require(bool cond, const(char)[] a...) @nogc pure nothrow
    {
        if (!cond)
            assert(0, a);
    }
}
