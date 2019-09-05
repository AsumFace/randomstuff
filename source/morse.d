/+--------------------Copyright Notice------------------------+\
|      Copyright:                                              |
|  - AsumFace (asumface@gmail.com) 2019                        |
|  Distributed under the Boost Software License, Version 1.0.  |
|  See accompanying file LICENSE or copy at                    |
|      https://www.boost.org/LICENSE_1_0.txt                   |
\+------------------------------------------------------------+/

/++
This module is an experiment for signal processing pipelines with a pull-based approach. It is fundamentally
structured with nodes the same as similar software like gnuradio.
+/

module morse;

import word;
import required;
import std.traits;
import std.typecons : Typedef;
import std.array : empty, popFront, front;

import std.stdio;

immutable(ubyte[16]) iLUT = [33, 5, 10, 10, 38, 28, 125, 26, 14, 0, 204, 187, 0, 18, 4, 1];
immutable(ubyte[2][62]) fLUT = [[19, 4], [3, 2], [19, 5], [29, 5], [33, 5], [6, 4], [1, 2], [11, 5], [17, 6], [20, 8], [46, 5], [51, 1], [26, 4], [25, 4], [0, 3], [16, 5], [7, 6], [29, 4], [11, 5], [10, 6], [37, 5], [3, 4], [20, 4], [30, 6], [32, 5], [41, 5], [2, 1], [3, 3], [17, 5], [7, 5], [0, 6], [29, 5], [0, 2], [25, 6], [40, 6], [7, 4], [20, 5], [2, 2], [11, 6], [7, 3], [24, 5], [38, 7], [2, 6], [7, 3], [10, 4], [25, 5], [11, 3], [20, 3], [32, 9], [0, 1], [4, 6], [16, 3], [2, 4], [15, 4], [15, 5], [12, 6], [1, 4], [8, 6], [18, 5], [15, 6], [1, 3], [2, 3]];
immutable packedCodes = [MorseUnit(1), MorseUnit(1), MorseUnit(2), MorseUnit(2), MorseUnit(1), MorseUnit(1), MorseUnit(2), MorseUnit(2), MorseUnit(1), MorseUnit(2), MorseUnit(2), MorseUnit(1), MorseUnit(2), MorseUnit(1), MorseUnit(2), MorseUnit(1), MorseUnit(2), MorseUnit(2), MorseUnit(2), MorseUnit(2), MorseUnit(1), MorseUnit(1), MorseUnit(1), MorseUnit(1), MorseUnit(1), MorseUnit(1), MorseUnit(1), MorseUnit(1), MorseUnit(2), MorseUnit(1), MorseUnit(2), MorseUnit(1), MorseUnit(1), MorseUnit(1), MorseUnit(1), MorseUnit(2), MorseUnit(2), MorseUnit(2), MorseUnit(1), MorseUnit(1), MorseUnit(1), MorseUnit(2), MorseUnit(1), MorseUnit(1), MorseUnit(2), MorseUnit(1), MorseUnit(2), MorseUnit(2), MorseUnit(2), MorseUnit(2), MorseUnit(2), MorseUnit(0)];

alias MorseUnit = Word!(1, 2);
alias MorseSequence = MorseUnit[];
alias BinaryLevel = Word!(1, 1);

struct MorseCode
{
    import std.format;
    enum Values : byte// values chosen to match ASCII as well as possible
    {
        A = 65,
        B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,
        n0 = 48,
        n1,n2,n3,n4,n5,n6,n7,n8,n9,
        dot = 46, comma = 44, colon = 58, semicolon = 59, question = 63, minus = 45, underscore = 95,
        parensOpen = 40, parensClose = 41, apostrope = 39, equals = 61, plus = 43, slash = 47, at = 64,
        ampersand = 38, dollar = 36, quote = 34, exclamation = 33, end = 4, error = 24, invite = 5,
        newPage = 12, ack = 6, wait = 19, space = 32, SOS = -1
    }
    Values value;
    ref typeof(this) opAssign(dchar arg)
    {
        import std.stdio;
        switch (arg)
        {
            case 'a': .. case 'z':
                value = cast(Values)(arg - ('a' - 'A'));
                break;
            case '0': .. case '9':
            case 'A': .. case 'Z':
            case '.':
            case ',':
            case ':':
            case ';':
            case '?':
            case '-':
            case '_':
            case '(':
            case ')':
            case '\'':
            case '=':
            case '+':
            case '/':
            case '@':
            case '&':
            case '$':
            case '"':
            case '!':
            case ' ':
                value = cast(Values)arg;
                break;
            default:
                require(0, format!"%s %s"(arg, cast(ulong)arg));
                break;
        }
        return this;
    }

    const(MorseSequence) sequenceRepr()
    {
        immutable salt = iLUT[hsh([value]) % iLUT.length];
        immutable idx = fLUT[saltedHash(value, salt) % fLUT.length][0];
        immutable len = fLUT[saltedHash(value, salt) % fLUT.length][1];
        return packedCodes[idx .. idx + len];
    }
}

struct StringToMorseSequenceFilter(alias _source)
{
    alias sources = AliasSeq!(_source);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        bool result = _source.ready0(shallRun);
        if (result == true)
            debug polled = true;
        return result;
    }

    const(MorseSequence) frontNPop0()
    {
        MorseCode code;
        //dchar b = frontNPop!(sources[0]);
        dchar b = _source.frontNPop0;
        code = b;
        return code.sequenceRepr;
    }

    void initialize()
    {
        _source.initialize;
    }
}

struct MorseSequencerFilter(alias _source)
{
    import std.array;
    alias sources = AliasSeq!(_source);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        while (seq.empty) // new symbol
        {
            ubyte blanks = 1; // one blank between symbols
            if (buf.empty) // new character
            {
                blanks = 3; // three blanks between characters
                if (sources[0].ready(shallRun))
                    buf = sources[0].frontNPop[];
                else
                    return false;
            }
            immutable sym = buf.front;
            buf.popFront;
            if (sym == MorseUnit(0)) // space character
                blanks = 7; // seven blanks for a space
            while (blanks > 0 && zeros > 0)
            {
                blanks -= 1;
                zeros -= 1;
            }
            foreach (i; 0 .. blanks)
                seqStore[i] = BinaryLevel(0);
            if (sym == MorseUnit(1))
            {
                foreach (i; 0 .. 1)
                    seqStore[i + blanks] = BinaryLevel(1);
                seq = seqStore[0 .. blanks + 1];
            }
            else if (sym == MorseUnit(2))
            {
                foreach (i; 0 .. 3)
                    seqStore[i + blanks] = BinaryLevel(1);
                seq = seqStore[0 .. blanks + 3];
            }
            if (sym == MorseUnit(0))
            {
                zeros = 7;
                seq = seqStore[0 .. blanks];
            }
            else
                zeros = 0;
        }
        debug polled = true;
        return true;
    }

    private const(Word!(1LU, 2LU))[] buf;
    private BinaryLevel[8] seqStore;
    private BinaryLevel[] seq;
    private ubyte zeros = 7;
    BinaryLevel frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        BinaryLevel result;
        result = seq.front;
        seq.popFront;
        return result;
    }

    void initialize()
    {
        sources[0].initialize;
    }
}

struct StringConstantSource(dstring constant, bool repeat)
{
    import std.array;
    private dstring buf = constant;

    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        if (!buf.empty || repeat)
        {
            debug polled = true;
            return true;
        }
        else
        {
            shallRun = false;
            return false;
        }
    }

    dchar frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        if (buf.empty)
        {
            if (repeat == false)
                require(0);
            buf = constant;
        }
        dchar result = buf.front;
        buf.popFront;
        return result;
    }

    void initialize()
    {}
}

struct ConsoleOutputSink(alias _source)
{
    alias sources = AliasSeq!(_source);
    bool shallRun;

    bool run()
    {
        import std.stdio;
        import core.thread;
        import std.datetime;
        import std.conv;
        uint limit = 4095;
        //static assert(is(SourceType!S : BinaryLevel));
        while (limit-- != 0)
        {
            if (!(sources[0].ready(shallRun)))
                break;
            auto data = sources[0].frontNPop;
            static if (is(SourceType!(typeof(sources[0])) : BinaryLevel))
            {
                if (data == BinaryLevel(0))
                    write("_");
                else if (data == BinaryLevel(1))
                    write("▄");
                else
                    require(0, data.to!string);
            }
            else
                writef!"%s|"(data);
        }
        stdout.flush;
        return limit < 1024 * 3 - 1;
    }

    void initialize()
    {
        sources[0].initialize;
        shallRun = true;
    }
}

struct SineFilter(alias _source)
{
    alias sources = AliasSeq!(_source);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        bool result = sources[0].ready(shallRun);
        if (result == true)
            debug polled = true;
        return result;
    }

    auto frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        import std.math;
        return sin(frontNPop(sources[0]));
    }

    void initialize()
    {
        _source.initialize;
    }
}

struct TrigoFilter(alias samplerate, alias frequency)
    if (is(typeof(samplerate) == float) || is(typeof(samplerate) == double))
{
    alias sources = AliasSeq!(frequency);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");
    alias T = typeof(samplerate);

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        bool result = frequency.ready(shallRun);
        if (result == true)
            debug polled = true;
        return result;
    }
    T state = 0.0f;
    T frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        import std.math;
        auto result = state;
        state += frequency.frontNPop / samplerate * cast(T)PI * 2.0f;
        if (state > cast(T)PI)
            state -= 2.0f * PI;
        return result;
    }

    void initialize()
    {
        frequency.initialize;
    }
}



struct RepetitionFilter(alias factor, alias _source)
{
    alias sources = AliasSeq!(_source);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        if (counter < factor || sources[0].ready(shallRun))
        {
            debug polled = true;
            return true;
        }
        else
            return false;
    }

    typeof(sources[0].frontNPop0()) buf;
    ulong counter = ulong.max;
    auto frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        if (counter < factor)
        {
            counter += 1;
            return buf;
        }
        else
        {
            buf = sources[0].frontNPop0;
            counter = 0;
            return buf;
        }
    }

    void initialize()
    {
        _source.initialize;
    }
}

struct BiquadConfig
{
    float b0 = 0;
    float b1 = 0;
    float b2 = 0;
    float a1 = 0;
    float a2 = 0;
}

struct BiquadFilter(BiquadConfig conf, alias _source)
{
    alias sources = AliasSeq!(_source);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        bool result = sources[0].ready(shallRun);
        if (result == true)
            debug polled = true;
        return result;
    }

    float z0 = 0;
    float z1 = 0;

    float frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        with (conf)
        {
            immutable x = sources[0].frontNPop;
            immutable float oldz0 = z0;
            immutable float oldz1 = z1;
            float y;
            y =  x * b0 + oldz0;
            z0 = x * b1 - y * a1 + oldz1;
            z1 = x * b2 - y * a2;
            return y;
        }
    }

    void initialize()
    {
        _source.initialize;
    }
}


mixin template Decl(T, string name)
{
    T _internal_name;
    mixin("alias " ~ name ~ " = _internal_name;");
}

template SourceType(alias S)
{
    alias SourceType = typeof(frontNPop(S));
}

struct PreciseDemuxerFilter(_sources...)
{
    import std.format;
    //S source;
    alias sources = _sources;

    static assert(is(typeof(sources[0].frontNPop()) : Word!(1, sources.length - 2)));
    static assert(!is(CommonType!(StaticMap!(SourceType, sources[1 .. $])) == void));

    void initialize()
    {
        static foreach (s; sources)
        {
            s.initialize;
        }
    }

    bool waitingForPop;
    bool waitingForSource;
    Word!(1, sources.length - 2) selector;

    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        if (!waitingForSource)
        {
            if (waitingForPop)
            {
                debug polled = true;
                return true;
            }
            else if (!(sources[0].ready(shallRun)))
                return false;
            else
            {
                selector = sources[0].frontNPop;
                waitingForSource = true;
                bool result = ready0(shallRun);
                if (result == true)
                {
                    debug polled = true;
                }
                return result;
            }
        }
        else
        {
            static foreach (i; 0 .. sources.length - 1)
            {
                if (selector == Word!(1, sources.length - 2)(i))
                {
                    auto result = sources[i + 1].ready(shallRun);
                    //mixin(format!"auto result = source%s.ready(shallRun);"(i + 1));
                    if (result)
                    {
                        waitingForPop = true;
                        waitingForSource = false;
                        debug require(polled == false);
                        debug polled = true;
                    }
                    return result;
                }
            }
        }
        require(0);
        assert(0);
    }

    auto frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        require(waitingForPop);
        waitingForPop = false;
        static foreach (i; 0 .. sources.length - 1)
        {
            if (selector == Word!(1, sources.length - 2)(i))
                return sources[i + 1].frontNPop;
        }
        require(0);
        assert(0);
    }
}

struct SynchronousDemuxerFilter(_sources...)
{
    import std.format;
    //S source;
    alias sources = _sources;

    static assert(is(typeof(sources[0].frontNPop()) : Word!(1, sources.length - 2)));
    static assert(!is(CommonType!(StaticMap!(SourceType, sources[1 .. $])) == void));

    void initialize()
    {
        static foreach (s; sources)
        {
            s.initialize;
        }
    }

    bool waitingForPop;
    bool waitingForSource;
    Word!(1, sources.length - 2) selector;

    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    static foreach (i; 0.. sources.length)
    {
        mixin(format!"bool polled%s = false;"(i));
    }

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        static foreach (i; 0 .. sources.length)
            mixin(format!q{
            //require(polled%1$s == false);
            if (polled%1$s || sources[%1$s].ready(shallRun))
                polled%1$s = true;
            else
            {
                //stderr.writefln!"%%s: source %1$s not ready"(__FUNCTION__);
                return false;
            }}(i));
        debug polled = true;
        return true;
    }

    auto frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        CommonType!(staticMap!(SourceType, sources[1 .. $])) result;
        auto selector = sources[0].frontNPop;
        polled0 = false;
        static foreach (i; 1 .. sources.length)
        {
            mixin(format!"require(polled%1$s == true); polled%1$s = false;"(i));
            if (selector == Word!(1, sources.length - 2)(i - 1))
                result = sources[i].frontNPop;
            else
                sources[i].frontNPop;
        }
        return result;
    }
}

struct ConstantSource(alias num)
{
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        //stderr.writefln!"constant ready";
        require(shallRun == true);
        debug require(polled == false);
        debug polled = true;
        return true;
    }

    auto frontNPop0()
    {
        //stderr.writefln!"constant frontNPop";
        debug require(polled == true);
        debug polled = false;
        return num;
    }

    void initialize()
    {}
}

struct CommandlineSource
{
    import core.sync.mutex;
    import std.experimental.allocator;
    import std.experimental.allocator.mallocator;
    import stack_container;
    import std.typecons;
    import core.atomic;
    import std.stdio;
    shared(Stack!dchar) buf;
    shared(Mutex) m;
    shared(bool*) shallRun;

    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);

        //stderr.writefln!"ready locking";
        m.lock;
        //stderr.writefln!"ready locked";
        if ((cast(Stack!dchar)buf).length > 0)
        {
            debug polled = true;
            return true;
        }
        else
        {
            //stderr.writefln!"ready unlocking";
            m.unlock;
            //stderr.writefln!"ready unlocked";
            shallRun = false;
            this.shallRun.atomicStore(cast(shared)&shallRun);
            return false;
        }
    }

    dchar frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        auto result = (cast(Stack!dchar)buf).back;
        (cast(Stack!dchar)buf).popBack;
        //stderr.writefln!"frontNPop unlocking";
        m.unlock;
        //stderr.writefln!"frontNPop unlocked";
        return result;
    }

    void initialize()
    {
        require(&this !is null, "Attempted to initialize null instance!");
        if (atomicLoad(m) is null) // if not already initializeialized
        {
            import std.concurrency;
            buf = cast(shared)Stack!dchar(4);
            m = cast(shared)make!Mutex(Mallocator.instance);
            spawn(&lineReaderThread, m, &buf, cast(shared)&this);
        }
    }

    void scheduleCallback()
    {
        auto cb = cast(bool*)atomicLoad(shallRun);
        if (cb !is null)
        {
            queueMut.lock;
            queue.pushFront(cb);
            queueMut.unlock;
        }
    }
}
import stack_container;
import core.sync.mutex;
import core.sync.semaphore;
void lineReaderThread(shared(Mutex) m, shared(Stack!dchar*) stack, shared(CommandlineSource*) base)
{
    import core.atomic;
    import std.stdio;
    auto input = stdin.byLine;

    while (true)
    {

        import std.uni : byCodePoint;
        auto dat = input.front.byCodePoint;
        //stderr.writefln!"thread locking";
        m.lock;
        //stderr.writefln!"thread locked";
        foreach (e; dat)
        {
            //stderr.writefln!"%s"(*stack);
            (cast(Stack!(dchar)*)stack).pushFront(e);
        }
        //stderr.writefln!"%s"(*stack);
        //stderr.writefln!"thread unlocking";
        m.unlock;
        //stderr.writefln!"thread unlocked";
        (cast(CommandlineSource*)base).scheduleCallback();
        //stderr.writefln!"thread waiting";
        input.popFront;
    }
}

alias PassthroughFilter(alias source) = Select!(source, 0);

struct FDMFilter(ulong size, ulong start, ulong stride, _sources...)
{
    import std.complex;
    alias sources = AliasSeq!(_sources);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    alias sourceType = Unqual!(CommonType!(staticMap!(SourceType, sources[0 .. $])));
    static assert(
        is(sourceType == Complex!double)
        || is(sourceType == Complex!float));

    sourceType[] spectrum;

    static foreach (i; 0.. sources.length)
    {
        import std.format;
        mixin(format!"bool polled%s = false;"(i));
    }

    static assert(!is(CommonType!(staticMap!(SourceType, sources[0 .. $])) == void));

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        static foreach (i; 0 .. sources.length)
            mixin(format!q{
            if (polled%1$s || sources[%1$s].ready(shallRun))
                polled%1$s = true;
            else
            {
                return false;
            }}(i));
        debug polled = true;
        return true;
    }

    auto frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        static foreach (i; 0 .. sources.length)
        {
            mixin(format!"require(polled%1$s == true); polled%1$s = false;"(i));
            require((start + i * stride) < (size / 2));
            spectrum[start + i * stride] = sources[i].frontNPop;
        }
        return spectrum;
    }

    void initialize()
    {
        import std.algorithm.mutation : fill;
        static foreach (s; sources)
            s.initialize;
        spectrum.length = size;
        spectrum[].fill(0.0);
    }
}

struct BinarySink(alias _source)
{
    alias sources = AliasSeq!(_source);

    bool shallRun;
    bool run()
    {
        uint limit = 4096;
        while (limit-- != 0)
        {
            if (!ready(sources[0], shallRun))
                break;
            import std.algorithm.mutation : copy;
            import std.stdio;
            auto data = sources[0].frontNPop;
            //stderr.writefln!"%s"(data);
            //static assert(is(typeof(data) : float));
            (cast(ubyte*)(&data))[0 .. data.sizeof].copy(stdout.lockingBinaryWriter);
        }
        return limit < 1024 * 3;
    }

    void initialize()
    {
        sources[0].initialize;
        shallRun = true;
    }
}

template isComplexLike(T)
{
    import std.complex;
    enum bool isComplexLike = is(typeof(T.init.re)) &&
        is(typeof(T.init.im));
}

struct IFFTFilter(ulong maxSize, alias _source)
{
    import std.range : ElementType;
    import std.complex;
    import std.typecons : scoped;
    import std.numeric;
    alias sources = AliasSeq!(_source);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    Fft fftObject;
    private alias SourceElementType = ElementType!(SourceType!_source);
    static assert(is(SourceElementType : Complex!double) || is(SourceElementType : Complex!float));
    SourceElementType[] buf;
    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        debug require(polled == false);
        if (_source.ready(shallRun))
        {
            debug polled = true;
            return true;
        }
        else
            return false;
    }

    auto frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        auto input = _source.frontNPop;
        fftObject.inverseFft(input[], buf[]);
        return buf[];
        /+if (!buf.empty)
        {
            auto result = buf.front;
            buf.popFront;
            return result;
        }
        else
        {
            auto input = _source.frontNPop;
            fftObject.inverseFft(input[], bufStore[]);
            buf = bufStore[0 .. $];
            return frontNPop;
        }+/
    }

    void initialize()
    {
        _source.initialize;
        buf.length = maxSize;
        fftObject = new Fft(maxSize);
    }
}

struct FadingFilter(ulong size, alias _source)
{
    alias sources = AliasSeq!(_source);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    SourceType!_source buf1;
    typeof(buf1) buf2;

    debug bool polled = false;

    ulong progress = size;
    bool ready0(ref bool shallRun)
    {
        import std.algorithm.mutation : copy, swap;
        debug require(polled == false);
        require(progress <= size);
        if (progress == size)
        {
            auto result = _source.ready(shallRun);
            if (result == false)
                return false;
            progress = 0;
            swap(buf1, buf2);
            _source.frontNPop[].copy(buf2[]);
            foreach (i; 0 .. size)
            {
                import std.math;
                import cgfm.math.funcs : lerp;
                buf1[i] = lerp(buf1[i], buf2[i], (-cos(cast(float)i/cast(float)size * cast(float)PI) + 1.0f) / 2.0f);
            }
        }

        debug polled = true;
        return true;
    }

    auto frontNPop()
    {
        debug require(polled == true);
        debug polled = false;
        return buf1[progress++];
    }

    void initialize()
    {
        _source.initialize;

        import std.algorithm.mutation : fill;
        buf1.length = size;
        buf2.length = size;
        buf2.fill(0);
    }
}

struct FallbackFilter(alias _source0, alias _source1)
{
    alias sources = AliasSeq!(_source0, _source1);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    bool lock0;
    debug bool polled = false;
    ubyte selector;
    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        if (lock0 && sources[0].ready(lock0))
        {
            selector = 0;
            debug polled = true;
            return true;
        }
        else if (sources[1].ready(shallRun))
        {
            selector = 1;
            debug polled = true;
            return true;
        }
        return false;
    }

    auto frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        if (selector == 0)
            //return frontNPop!(sources[0]);
            return sources[0].frontNPop;
        else if (selector == 1)
            //return frontNPop!(sources[1]);
            return sources[1].frontNPop;
        else
            require(0);
        assert(0);
    }

    void initialize()
    {
        _source0.initialize;
        _source1.initialize;
        lock0 = true;
    }
}

struct DiffQuadrature4Filter(alias _source)
{
    alias sources = AliasSeq!(_source);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        //return ready!(sources[0])(shallRun);
        return sources[0].ready(shallRun);
    }

    Word!(2, 1) buf;
    ubyte state;

    Word!(2, 1) frontNPop0()
    {
        state += 1;
        state %= 2;
        buf[state] = _source.frontNPop[0];
        typeof(return) result = buf;
        /+immutable bit = sources[].frontNPop;// frontNPop!(sources[0]);
        if (bit == BinaryLevel(0))
            state++;
        else if (bit == BinaryLevel(1))
            state--;
        else
            require(0);
        state &= 0b11;
        if (state > 1)
            result[1] = cast(int)true;
        else
            result[1] = cast(int)false;
        if (state == 1 || state == 2)
            result[0] = cast(int)true;
        else
            result[0] = cast(int)false;+/
        return result;
    }

    void initialize()
    {
        _source.initialize;
    }
}

struct WordSplitterFilter(alias _source)
{
//    S source;

    bool consumed = true;
    bool consumed1 = true;
    Word!(2, 1) buf;

    import std.stdio;
    /+bool ready(ref bool shallRun)
    {
        auto result = _ready(shallRun);
        stderr.writefln!"ready %s %s %s"(result, consumed, consumed1);
        return result;
    }

    bool ready1(ref bool shallRun)
    {
        auto result = _ready1(shallRun);
        stderr.writefln!"ready1 %s %s %s %s"(result, consumed, consumed1, !consumed1 && consumed);
        return result;
    }+/

    alias sources = AliasSeq!(_source);
    alias readys = AliasSeq!("ready0", "ready1");
    alias frontNPops = AliasSeq!("frontNPop0", "frontNPop1");

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        if (consumed && consumed1)
            return sources[0].ready(shallRun);
        if (!consumed && consumed1 || !consumed && !consumed1)
            return true;
        else
            return false;
    }

    bool ready1(ref bool shallRun)
    {
        if (consumed && consumed1)
        {
            //stderr.writefln!"0";
            return sources[0].ready(shallRun);
        }
        if (!consumed1 && consumed || !consumed1 && !consumed)
        {
            //stderr.writefln!"1";
            return true;
        }
        else
        {
            //stderr.writefln!"2";
            return false;
        }
    }

    BinaryLevel frontNPop0()
    {
        //stderr.writefln!"frontNPop";
        if (consumed && consumed1)
        {
            buf = sources[0].frontNPop;
            consumed = false;
            consumed1 = false;
        }
        consumed = true;
        //stderr.writefln!"%s %s"(consumed, consumed1);
        return BinaryLevel(buf[0]);
    }

    BinaryLevel frontNPop1()
    {
        //stderr.writefln!"frontNPop1";
        if (consumed && consumed1)
        {
            buf = sources[0].frontNPop;
            consumed = false;
            consumed1 = false;
        }
        consumed1 = true;
        //stderr.writefln!"%s %s"(consumed, consumed1);
        return BinaryLevel(buf[1]);
    }

    void initialize()
    {
        sources[0].initialize;
    }
}

struct ThrottleFilter(ulong rate, alias _source)
{
    import std.datetime;

    alias sources = AliasSeq!(_source);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    MonoTime lastTime;
    ulong budget;
    bool sourceReady;
    debug bool polled = false;
    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        if (sourceReady || sources[0].ready(shallRun))
        {
            sourceReady = true;
            if (budget > 0)
            {
                debug polled = true;
                return true;
            }
            else
            {
                auto ct = MonoTime.currTime;
                auto diff = (ct - lastTime).total!"msecs";
                auto budgetdiff = rate * diff / 1_000_000;
                lastTime += (budgetdiff * 1_000_000 / rate).dur!"msecs";
                budget += budgetdiff;
                //if (budget > 10)
                //    budget = 10;
                bool result = budget > 0;
                if (result == true)
                    debug polled = true;
                return result;
            }
        }
        else
            return false;
    }

    auto frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        sourceReady = false;
        budget -= 1;
        return sources[0].frontNPop;
    }

    void initialize()
    {
        sources[0].initialize;
        lastTime = MonoTime.currTime;
    }
}

struct BitstuffingFilter(alias threshold, alias _source)
{
    alias sources = AliasSeq!(_source);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    static assert(is(SourceType!_source : BinaryLevel));
    typeof(threshold) counter;
    BinaryLevel prevState;

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        if (counter == threshold || sources[0].ready(shallRun))
        {
            debug polled = true;
            return true;
        }
        else
            return false;
    }

    BinaryLevel frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        if (counter == threshold)
        {
            counter = 1;
            prevState = ~prevState;
            return prevState;
        }
        else
        {
            auto newState = sources[0].frontNPop;
            if (newState == prevState)
                counter += 1;
            else
            {
                counter = 1;
                prevState = newState;
            }
            return newState;
        }
    }

    void initialize()
    {
        sources[0].initialize;
    }
}

struct BinaryOpFilter(string op, _sources...)
{
    import std.format;
    alias sources = _sources;
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    static foreach (i; 0.. sources.length)
    {
        mixin(format!"bool polled%s = false;"(i));
    }

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        static foreach (i; 0 .. sources.length)
            mixin(format!q{
            if (!polled%1$s)
            {
                auto result = sources[%1$s].ready(shallRun);
                //stderr.writefln!"result %%s: %%s %%s"(i, result, shallRun);
                if (result == true)
                    polled%1$s = true;
                else
                {
                    //stderr.writefln!"%%s: source %1$s not ready"(__FUNCTION__);
                    return false;
                }
            }
            /+else
            {
                stderr.writefln!"%%s: source %1$s not ready"(__FUNCTION__);
                return false;
            }+/
            }(i));
        //stderr.writefln!"BinaryOpFilter %s ready"(op);
        debug polled = true;
        return true;
    }

    auto frontNPop0()
    {
        //stderr.writefln!"BinaryOpFilter %s frontNPop"(op);
        debug require(polled == true);
        debug polled = false;
        require(polled0 == true);
        polled0 = false;
        //stderr.writefln!"queried polled0: %s"(polled0);
        auto result = sources[0].frontNPop;
        static foreach (i; 1 .. sources.length)
        {
            mixin(format!"require(polled%1$s == true); polled%1$s = false;"(i));
            mixin("result "~ op ~"= sources[i].frontNPop;");
        }
        return result;
    }

    void initialize()
    {
        static foreach (s; sources)
            s.initialize;
    }
}

struct Select(alias _source, ulong idx)
{
    import std.conv;
    enum formattedDigit = idx == 0 ? "" : idx.to!string;

    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");
    alias sources = AliasSeq!(_source);

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        bool result = sources[0].ready!idx(shallRun);
        if (result == true)
            debug polled = true;
        return result;
    }

    auto frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        return sources[0].frontNPop!idx;
    }

    void initialize()
    {
        static if (isPointer!(typeof(sources[0])))
            require(sources[0] !is null);
        sources[0].initialize;
    }
}

struct InterpolationFilter(alias _variable, alias _a, alias _b)
{
    alias sources = AliasSeq!(_variable, _a, _b);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    bool polledVariable;
    bool polledA;
    bool polledB;

    debug bool polled;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        if (polledVariable || _variable.ready(shallRun))
            polledVariable = true;
        else
            return false;
        if (polledA || _a.ready(shallRun))
            polledA = true;
        else
            return false;
        if (polledB || _b.ready(shallRun))
            polledB = true;
        else
            return false;
        debug polled = true;
        return true;
    }

    auto frontNPop0()
    {
        import cgfm.math.funcs : lerp;
        debug require(polled == true);
        debug polled = false;
        polledVariable = false;
        polledA = false;
        polledB = false;
        return lerp(_a.frontNPop(), _b.frontNPop(), _variable.frontNPop());
    }

    void initialize()
    {
        _variable.initialize;
        _a.initialize;
        _b.initialize;
        polledVariable = false;
        polledA = false;
        polledB = false;
    }
}

struct RampSource(T, ulong modulo)
    if (is(T == float) || is(T == double))
{
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        require(shallRun == true);
        debug require(polled == false);
        debug polled = true;
        return true;
    }

    ulong counter;

    T frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        T result = cast(T)(counter) / cast(T)(modulo - 1);
        counter += 1;
        counter %= modulo;
        return result;
    }

    void initialize()
    {
        counter = 0;
    }
}

struct SynchroForkFilter(ulong num, alias _source)
{
    alias sources = AliasSeq!(_source);
    bool polledSource = false;
    SourceType!(_source) buf;
    ulong popped;
    static foreach (i; 0 .. num)
    {
        import std.format;
        mixin(format!q{
        bool consumed%1$s = false;
        debug bool polled%1$s = false;
        bool ready%1$s(ref bool shallRun)
        {
            debug require(polled%1$s == false);
            require(popped <= num);
            if (popped == num)
            {
                popped = 0;
                resetConsumedVars;
                polledSource = false;
            }
            if (!polledSource)
            {
                bool result = _source.ready(shallRun);
                if (result == true)
                {
                    polledSource = true;
                    buf = _source.frontNPop;
                }
            }
            if (!consumed%1$s && polledSource)
            {
                debug polled%1$s = true;
                //stderr.writefln!"%%s: %%s ready"(__FUNCTION__, i);
                return true;
            }
            else
            {
                //stderr.writefln!"%%s: %%s not ready: pS:%%s p:%%s"(__FUNCTION__, i, polledSource, popped);
                return false;
            }
        }

        auto frontNPop%1$s()
        {
            debug require(polled%1$s == true);
            debug polled%1$s = false;
            require(consumed%1$s == false);
            consumed%1$s = true;
            popped += 1;
            require(popped <= num);
            return buf;
        }}(i));
    }

    private void resetConsumedVars()
    {
        static foreach (i; 0 .. num)
        {
            mixin(format!`consumed%1$s = false;`(i));
        }
    }


    import std.range : iota;
    import std.algorithm.iteration : map;
    import std.conv : to;
    import std.array : array;
    mixin(format!`alias readys = AliasSeq!(%("ready%s"%|, %));`(iota(0, num)));
    mixin(format!`alias frontNPops = AliasSeq!(%("frontNPop%s"%|, %));`(iota(0, num)));

    void initialize()
    {
        _source.initialize;
    }
}

struct MapFilter(alias Fun, alias _source)
{
    alias sources = AliasSeq!(_source);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    bool ready0(ref bool shallRun)
    {
        return _source.ready(shallRun);
    }

    auto frontNPop0()
    {
        return Fun(_source.frontNPop);
    }

    void initialize()
    {
        _source.initialize;
    }
}

/+auto frontNPop(ulong idx = 0, Input)(ref Input input)
{
    return frontNPop!(input, idx);
}+/
auto frontNPop(ulong idx = 0, Input)(ref Input input)
{
    static assert(!(is(typeof(return) == void)));
    mixin("return input." ~ input.frontNPops[idx] ~ ";");
}

/+auto ready(ulong idx = 0, Input)(ref Input input, ref bool shallRun)
{
    return ready!idx(input, shallRun);
}+/
bool ready(ulong idx = 0, Input)(ref Input input, ref bool shallRun)
{
    mixin("return input." ~ input.readys[idx] ~ "(shallRun);");
}

struct BitPickingFilter(ubyte pos, alias _source)
{
    alias sources = AliasSeq!(_source);
    alias readys = AliasSeq!("ready0");
    alias frontNPops = AliasSeq!("frontNPop0");

    debug bool polled = false;

    bool ready0(ref bool shallRun)
    {
        debug require(polled == false);
        bool result = _source.ready(shallRun);
        if (result == true)
            debug polled = true;
        return result;
    }

    BinaryLevel frontNPop0()
    {
        debug require(polled == true);
        debug polled = false;
        return BinaryLevel((_source.frontNPop & (1uL << pos)) > 0 ? 1 : 0);
    }

    void initialize()
    {
        _source.initialize;
    }
}

struct NullSink(alias _source)
{
    alias sources = AliasSeq!(_source);

    bool shallRun;
    bool run()
    {
        uint limit = 4096;
        while (limit-- != 0)
        {
            import core.atomic;
            if (!ready(sources[0], shallRun))
                break;
            sources[0].frontNPop;
        }
        return limit < 1024 * 3;
    }

    void initialize()
    {
        sources[0].initialize;
        shallRun = true;
    }
}

__gshared Mutex queueMut;
__gshared Stack!(bool*) queue;

/+void main()
{
    import std.stdio;
    import std.meta;
    import std.format;
    import core.atomic;
    import std.range;
    import std.typecons;
    import std.complex;
    import std.random;
    import std.experimental.allocator.mallocator;
    import std.experimental.allocator;
    queueMut = make!Mutex(Mallocator.instance);

    enum l = 48000/1;
    enum width = 64;
    enum transSize = 512;

    //CommandlineSource commands;
    ConstantSource!(Alias!(10866815317393612458uL)) commands;
    MapFilter!(n => uniform!ulong, commands) rep;
    SynchroForkFilter!(width, rep) dataByte;

    static foreach (i; 0 .. width)
        mixin(format!q{
        Select!(dataByte, %1$s) dataByte%1$s;
        BitPickingFilter!(%1$s, dataByte%1$s) picked%1$s;
        MapFilter!(n => n[0] == WrappingDigit!1(1) ? complex(1.0f) : complex(-1.0f), picked%1$s) transformed%1$s;
        }(i));

    mixin(format!`FDMFilter!(transSize, 1, 3, %(transformed%s, %)) spectrum;`(iota(0, width)));
    IFFTFilter!(transSize, spectrum) synth;
    FadingFilter!(transSize, synth) faded;
    ConstantSource!(Alias!(16.0f/1.0f)) scaler;
    BinaryOpFilter!("*", faded, scaler) scaled;

    ThrottleFilter!(48_000__000, scaled) throttled;
    BinarySink!(throttled) sink;

    sink.initialize;

    while (true)
    {
        import core.thread;
        bool active = false;
        if (sink.shallRun)
        {
            if (sink.run)
            {
                active = true;
            }
        }
        //stderr.writefln!"%s"(sink.shallRun);
        if (active == false)
        {
            Thread.sleep(10.msecs);
        }
        queueMut.lock;
        //stderr.writefln!"%s %s"(queue.length, sink.shallRun);
        foreach (ptr; queue)
        {
            //stderr.writefln!"%s"(ptr);
            *ptr = true;
        }
        queue.clear;
        queueMut.unlock;
    }
}+/

private ushort saltedHash(MorseCode.Values arg, ubyte salt)
{
    import fnv;
    ubyte[2] dat;
    dat[0] = arg;
    dat[1 .. 2] = (cast(ubyte*)&salt)[0 .. 1];
    auto hash = hsh(dat[]);
    return cast(ushort)hash;
}

private ushort hsh(const(ubyte)[] dat)
{
    import fnvhash;
    auto hash = fnv!6(dat[]);
    return cast(ushort)hash;
}
