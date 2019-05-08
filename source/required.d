module required;

version(LDC)
{
    import ldc.llvmasm;

    void require(bool cond, const(char)[] a...) @nogc pure nothrow @safe
    {
        if (!cond)
        {
            version(assert)
                assert(0, a);
            else
                int _ = __ir_pure!("unreachable", int)(0);
        }
    }
}
else version(GNU)
{
    import gcc.builtins;
    void require(bool cond, const(char)[] a...) @nogc pure nothrow @safe
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
    void require(bool cond, const(char)[] a...) @nogc pure nothrow @safe
    {
        if (!cond)
            assert(0, a);
    }
}
