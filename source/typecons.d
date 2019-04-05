module typecons;

struct Ref(T)
{
    private T* _ptr;

    ref T _value() @property
    {
        return *_ptr;
    }

    this(ref T value)
    {
        _ptr = &value;
    }

    alias _value this;
}
