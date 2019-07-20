import bindbc.glfw;
import bindbc.opengl;
//import arsd.simpledisplay;
import arsd.nanovega;
import std.stdio;
import core.thread;
import std.string;
import required;
import cgfm.math;

void main()
{
    import sedectree;

    auto tree = sedecTree!(uint, c => cast(bool)((c.x*c.y)%2));

    Vector!(uint, 2)[] points = new Vector!(uint, 2)[10000];

    foreach (ref e; points[])
    {
        e = Vector!(uint, 2)(uniform!uint, uniform!uint);
    }

    foreach (i; 0 .. 10000)
    {
        tree[points[i]] = uniform!int < 0;
    }
    foreach (i, p; points[])
    {
        writefln!"%s %s"(i, tree[p]);
    }
    ubyte[] written = tree.packNode(tree.root);



    foreach (x; 0 .. 10)
    {
        foreach (y; 0 .. 10)
        {
            bool xv;
            if (y < 5)
                xv = true;
            else
                xv = false;
            tree[x, y] = xv;
        }
    }

    foreach (y; 0 .. 10)
    {
        foreach (x; 0 .. 10)
        {
            writef!"%b"(tree[x, y]);
        }
        writeln;
    }



    Thread.sleep(500.msecs);
    sedecAllocator.reportStatistics(stderr);
    Thread.sleep(10000.seconds);

    if (true ? true : false)
        assert(0, "end of program");

    import std.datetime;
    if (glfwInit == false)
        assert(0, "GLFW initialization failed");
    else
        writefln!"GLFW initialized!";
    //glfwSetErrorCallback(&error_callback);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 2);
    glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, GL_TRUE);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
    glfwWindowHint(GLFW_DOUBLEBUFFER, GL_TRUE);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    int width = 800;
    int height = 600;
    GLFWwindow* window = glfwCreateWindow(width, height, "NanoVega Test", null, null);
    if (window is null)
        assert(0, "GLFW window creation failure");
    else
        stderr.writefln!"GLFW window created!";
    scope(exit) glfwDestroyWindow(window);
    glfwMakeContextCurrent(window);
    glfwSetInputMode(window, GLFW_STICKY_MOUSE_BUTTONS, GLFW_TRUE);
    glfwSwapInterval(1);
    NVGContext nvg = nvgCreateContext();
    loadOpenGL();
    scope(exit) nvg.kill;

    uint vbo;
    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, 0, null, GL_STATIC_DRAW);
    uint vao;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);

    import std.string;
    loadOpenGL();
    stderr.writefln!"%s"(glGetString(GL_VERSION).fromStringz);

    auto log = File("dat", "w");

    import core.thread;
    bool exit = false;
    auto expiration = MonoTime.currTime + 3000000.msecs;



    window.glfwSetScrollCallback(&scrollCallback);
    window.glfwSetKeyCallback(&keyCallback);



    Button!(false) a;
    ZoomableMap b;
    b.bg = createImage(nvg, "/tmp/test.png", NVGImageFlag.GenerateMipmaps, NVGImageFlag.NoFiltering);
    keyDelegate = &(b.key);
    scrollDelegate = &(b.scroll);

    Button!(false) c;
    SidebarFrame!(a, b, c) mainFrame;
    mainFrame.width = width;
    mainFrame.height = height;
    mainFrame.resetLayout;
    mainFrame.x0 = 0;
    mainFrame.y0 = 0;

    b.tScale = 20;
    b.tPos = vec2f(b.width*b.tScale/2, b.height*b.tScale/2.0);
    b.scaleTime = 1.0;
    b.posTime = 1.0;
//    mainFrame.rcut = 300;
//    mainFrame.lcut = 100;
    bool currDragging = false;
    bool lastLmb = false;
    float lastxcur = 0;
    float lastycur = 0;
    long beginDrawTime = MonoTime.currTime.ticks;
    long delay = 0;
    while (!exit)
    {
        double xcur;
        double ycur;
        window.glfwGetCursorPos(&xcur, &ycur);
        stderr.writefln!"cursor: %s"(vec2d(xcur, ycur));
        bool lmb = !!glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_LEFT);

        mainFrame.progress(1.seconds / 60);
        if (xcur < width && xcur > 0 && ycur > 0 && ycur < height)
        {
            if (lmb == true && lastLmb == false)
            {
                currDragging = false;
                //stderr.writefln!"click event";
                mainFrame.click(true, xcur, ycur);
            }
            else if (lmb == false && lastLmb == true)
            {
                currDragging = false;
                //stderr.writefln!"release event";
                mainFrame.click(false, xcur, ycur);
            }
            else if (lmb == true && lastLmb && (xcur != lastxcur || ycur != lastycur) && !currDragging)
            {
                currDragging = true;
                //stderr.writefln!"drag event";
                mainFrame.drag(xcur, ycur);
            }
            else
            {
                //currDragging = false;
                //stderr.writefln!"point event";
                mainFrame.pointer(xcur, ycur);
            }
        }
        else
            currDragging = false;
        lastLmb = lmb;
        lastxcur = xcur;
        lastycur = ycur;

        glClearColor(0, 0, 0, 0);
        glClear(glNVGClearFlags);
        {
            nvg.beginFrame(width, height);
            scope(exit) nvg.endFrame();

            mainFrame.draw(nvg);


            nvg.beginPath();
            nvg.roundedRect(xcur - 5, ycur - 5, 10, 10, 2);
            nvg.fillPaint = nvg.linearGradient(0, 0, width, height, nvgHSLA(0.0, 0.0, 0.0, 0.0), nvgHSLA(0.0, 0.0, 0.0, 0.0));
            nvg.fill();
            nvg.strokeColor = NVGColor.black;
            nvg.strokeWidth = 1;
            nvg.stroke();
        }
        mainFrame.end;
        glfwSwapBuffers(window);
        long swapEnd = MonoTime.currTime.ticks;
        long drawTime = swapEnd - beginDrawTime;
        glFinish();
        beginDrawTime = MonoTime.currTime.ticks;
        long finTime = beginDrawTime - swapEnd;
        //Thread.sleep(100.msecs);

        float ratio = cast(float)finTime/drawTime;
        import std.format;
        log.lockingTextWriter.formattedWrite!"%s,%s\n"(drawTime, finTime);
        if (ratio > 0.2f)
        {
            delay += 100;
        }
        else if (ratio < 0.10f)
        {
            delay -= 100;
        }
        else if (ratio > 0.15)
        {
            delay += 1;
        }
        else if (ratio < 0.15)
        {
            delay -= 1;
        }
        if (delay < 0)
            delay = 0;
        //writefln!"Draw: %10s; Finish: %10s; Ratio: %10s; Delay: %10s"(drawTime, finTime, cast(float)finTime/drawTime, delay);
  //      Thread.sleep((delay).usecs);

        if (MonoTime.currTime > expiration)
            exit = true;
        glfwPollEvents();
        {
            int nwidth;
            int nheight;
            window.glfwGetWindowSize(&nwidth, &nheight);
            if (nwidth != width)
            {
                width = nwidth;
                mainFrame.width = nwidth;
                glViewport(0, 0, width, height);
                //stderr.writefln!"updated size to %s %s"(width, height);
            }
            if (nheight != height)
            {
                height = nheight;
                mainFrame.height = nheight;
                glViewport(0, 0, width, height);
                //stderr.writefln!"updated size to %s %s"(width, height);
            }
        }
        //stderr.writefln!"---";
    }
}

struct Draggable
{
    void* data;
    const(char)[] type;
}

struct Button(bool toggle)
{
    int _width;
    int _height;
    int _x0;
    int _y0;

    int x0(int x)
    { return _x0 = x; }
    int y0(int y)
    { return _y0 = y; }
    int width(int width)
    { return _width = width; }
    int height(int height)
    { return _height = height; }

    int x0() const
    { return _x0; }
    int y0() const
    { return _y0; }
    int width() const
    { return _width; }
    int height() const
    { return _height; }

    bool activated;
    bool pointedTo;

    import std.datetime;
    void progress(Duration time)
    {}

    void click(bool press, float x, float y)
    {
        static if (toggle)
        {
            if (press)
                activated = !activated;
        }
        static if (!toggle)
        {
            if (press)
                activated = true;
            else
                activated = false;
        }
        pointedTo = true;
    }

    void pointer(float x, float y)
    {
        pointedTo = true;
    }

    Draggable drag(float x, float y)
    {
        if (!toggle && activated)
            activated = false;
        return Draggable(null);
    }

    void draw(NVGContext nvg)
    {
        NVGColor fillColor;
        if (activated)
            fillColor = nvgHSLA(0.0, 0.39, 0.87, 1.0);
        else
            fillColor = nvgHSLA(0.81, 0.39, 0.87, 1.0);
        nvg.beginPath();
        nvg.roundedRect(x0, y0, /+x0 +/ width, /+y0 +/ height, 5);
        nvg.fillPaint = nvg.linearGradient(x0, y0, /+x0 +/ width, /+y0 +/ height, fillColor, fillColor);
        nvg.fill();
        if (pointedTo)
            nvg.strokeColor = NVGColor.white;
        else
            nvg.strokeColor = NVGColor.blue;
        nvg.strokeWidth = 2;
        nvg.stroke();

    }

    void end()
    {
        if (!toggle && pointedTo == false)
        {
            activated = false;
        }
        pointedTo = false;
    }

    invariant
    {
        //stderr.writefln!"Button: x0 %s; y0 %s; width %s; height %s;"(_x0, _y0, _width, _height);
        assert(_width >= 0);
        assert(_height >= 0);
    }
}

struct SidebarFrame(alias lwidget, alias cwidget, alias rwidget)
{
    int _width;
    int _height;
    int _x0;
    int _y0;

    private void resetLayout()
    {
        cwidget.height = _height;
        rwidget.height = _height;
        lwidget.height = _height;
        cwidget.width = _width / 3;
        rwidget.width = _width / 3;
        lwidget.width = _width / 3;
        cwidget.x0 = x0 + _width / 3;
        rwidget.x0 = x0 + _width / 3 * 2;
        rwidget.width = rwidget.width + (_width - (_width / 3 * 3));
    }

    import std.datetime;
    void progress(Duration time)
    {
        lwidget.progress(time);
        cwidget.progress(time);
        rwidget.progress(time);
    }

    int x0(int x)
    {
        lwidget.x0 = lwidget.x0 + x - _x0;
        cwidget.x0 = cwidget.x0 + x - _x0;
        rwidget.x0 = rwidget.x0 + x - _x0;
        return _x0 = x;
    }
    int y0(int y)
    {
        lwidget.y0 = y;
        cwidget.y0 = y;
        rwidget.y0 = y;
        return _y0 = y;
    }
    int width(int width)
    {
        immutable nCwidgetWidth = cwidget.width + (width - _width);
        _width = width;
        if (nCwidgetWidth >= 0)
        {
            cwidget.width = nCwidgetWidth;
            rwidget.x0 = x0 + lwidget.width + cwidget.width;
        }
        else
        {
            resetLayout;
        }
        return width;
    }
    int height(int height)
    {
        lwidget.height = height;
        cwidget.height = height;
        rwidget.height = height;
        return _height = height;
    }
    int x0() const
    { return _x0; }
    int y0() const
    { return _y0; }
    int width() const
    { return _width; }
    int height() const
    { return _height; }

    import std.algorithm.comparison : clamp;
    void lcut(int x)
    {
        auto _lcut = clamp(x - x0, 0, lwidget.width + cwidget.width);
        lwidget.width = _lcut;
        cwidget.width = _width - lwidget.width - rwidget.width;
        cwidget.x0 = x0 + lwidget.width;
    }
    void rcut(int x)
    {
        auto _rcut = clamp(x - x0, lwidget.width, _width);
        rwidget.width = _width - _rcut;
        cwidget.width = _width - lwidget.width - rwidget.width;
        rwidget.x0 = x0 + _rcut;
    }

    invariant
    {
        //stderr.writefln!"SiderBarFrame: x0 %s; y0 %s; width %s; height %s;"(_x0, _y0, _width, _height);
        assert(lwidget.width <= _width);
        assert(cwidget.width <= _width);
        assert(rwidget.width <= _width);
        assert(lwidget.width + cwidget.width + rwidget.width <= _width);
     //        format!"%s+%s+%s=%s>%s"(lwidget.width, cwidget.width, rwidget.width, lwidget.width + cwidget.width + rwidget.width, width));
    }

    enum Regions
    {
        left,
        center,
        right,
        leftBorder,
        rightBorder
    }

    enum ResizeModes
    {
        none,
        left,
        right
    }

    ResizeModes resizeMode;

    private Regions detRegion(float x, float y)
    {
        bool rightOfLeftBar = x > (lwidget.x0 + lwidget.width + 10);
        bool leftOfRightBar = x < (rwidget.x0 - 10);
        bool inLeftBar = x < (lwidget.x0 + lwidget.width - 10);
        bool inRightBar = x > (rwidget.x0 + 10);

        if (inLeftBar)
            return Regions.left;
        if (inRightBar)
            return Regions.right;
        if (rightOfLeftBar && leftOfRightBar)
            return Regions.center;
        if (rightOfLeftBar)
            return Regions.rightBorder;
        if (leftOfRightBar)
            return Regions.leftBorder;
        return Regions.leftBorder;
//        require(0);
//        return Regions.init; // unreachable
    }

    void pointer(float x, float y)
    {
        import std.algorithm.comparison : clamp;
        if (resizeMode == ResizeModes.none)
        {
            with (Regions) switch (detRegion(x, y))
            {
            case center:
                cwidget.pointer(x, y);
                break;
            case left:
                lwidget.pointer(x, y);
                break;
            case right:
                rwidget.pointer(x, y);
                break;
            default:
                break;
            }
        }
        else if (resizeMode == ResizeModes.left)
            lcut = cast(int)x;
        else if (resizeMode == ResizeModes.right)
            rcut = cast(int)x;
        else
            require(0);
    }

    void click(bool press, float x, float y)
    {
        if (!press && resizeMode != ResizeModes.none)
        {
            resizeMode = ResizeModes.none;
            return;
        }
        with (Regions) switch (detRegion(x, y))
        {
        case leftBorder:
        case rightBorder:
            break;
        case center:
            cwidget.click(press, x, y);
            break;
        case left:
            lwidget.click(press, x, y);
            break;
        case right:
            rwidget.click(press, x, y);
            break;
        default:
            require(0);
        }
    }

    Draggable drag(float x, float y)
    {
        //stderr.writefln!"detRegion: %s"(detRegion(x, y));
        with (Regions) switch (detRegion(x, y))
        {

        case leftBorder:
            resizeMode = ResizeModes.left;
            return Draggable(null);
        case rightBorder:
            resizeMode = ResizeModes.right;
            return Draggable(null);
        case center:
            return cwidget.drag(x, y);
        case left:
            return lwidget.drag(x, y);
        case right:
            return rwidget.drag(x, y);
        default:
            require(0);
        }
        return Draggable.init; // unreachable
    }

    void draw(T)(T nvg)
    {
        lwidget.draw(nvg);
        rwidget.draw(nvg);
        cwidget.draw(nvg);

//         stderr.writefln!"resizeMode %s;"(resizeMode);
        //stderr.writefln!"lcut %s; rcut %s; width %s; height %s; x0 %s; y0 %s;"(lcut, rcut, width, height, x0, y0);
        //stderr.writefln!"lwidget -- width %s; height %s; x0 %s; y0 %s;"(lwidget.width, lwidget.height, lwidget.x0, lwidget.y0);
        //stderr.writefln!"cwidget -- width %s; height %s; x0 %s; y0 %s;"(cwidget.width, cwidget.height, cwidget.x0, cwidget.y0);
        //stderr.writefln!"rwidget -- width %s; height %s; x0 %s; y0 %s;"(rwidget.width, rwidget.height, rwidget.x0, rwidget.y0);
    }

    void end()
    {
        lwidget.end();
        cwidget.end();
        rwidget.end();
    }
}


void delegate(GLFWwindow* window, vec2f offset) scrollDelegate;
extern(C) void scrollCallback(GLFWwindow* window, double xoffset, double yoffset) nothrow
{
    import std.exception;
    if (scrollDelegate !is null)
        assumeWontThrow(scrollDelegate(window, vec2f(xoffset, yoffset)));
}


void delegate(GLFWwindow* window, int key, int scancode, int action, int mods) keyDelegate;
extern(C) void keyCallback(GLFWwindow* window, int key, int scancode, int action, int mods) nothrow
{
    import std.exception;
    if (key == 256)
        assert(0);
    if (keyDelegate !is null)
        assumeWontThrow(keyDelegate(window, key, scancode, action, mods));
}

struct ZoomableMap
{
    int x0;
    int y0;
    int width;
    int height;
    float sScale = 1;
    float tScale = 1;
    vec2f sPos = vec2f(0,0);
    vec2f tPos = vec2f(0,0);

    float scaleTime = 0;
    float posTime = 0;

    private vec2f center()
    {
        return vec2f(
            width / 2.0f,
            height / 2.0f);
    }

    private vec2f size()
    {
        return vec2f(width, height);
    }

    private vec2f topLeft()
    {
        return vec2f(x0, y0);
    }

    vec2f cursor;

    void key(GLFWwindow* window, int key, int scancode, int action, int mods)
    {
        stderr.writefln!"key %s; scancode %s; action %s"(key, scancode, action);
        if (action == GLFW_PRESS || action == GLFW_REPEAT)
        {
            sPos = currPos;
            switch (key)
            {
            case GLFW_KEY_UP:
                tPos.y -= 10 * currScale;
                break;
            case GLFW_KEY_DOWN:
                tPos.y += 10 * currScale;
                break;
            case GLFW_KEY_RIGHT:
                tPos.x += 10 * currScale;
                break;
            case GLFW_KEY_LEFT:
                tPos.x -= 10 * currScale;
                break;
            default:
                break;
            }
            posTime = 1.0;
        }
    }

    private vec2f trTopLeft()
    {
        return tPos;// - trSize / 2.0f;
    }

    private vec2f trBottomRight()
    {
        return tPos + trSize;// / 2.0f;
    }

    private vec2f trSize()
    {
        return size * tScale;
    }

    float zoomFactor = 0.9;
    void scroll(GLFWwindow* window, vec2f offset)
    {
        double xcur, ycur;
        window.glfwGetCursorPos(&xcur, &ycur);
        immutable vec2f cursor = vec2f(xcur, ycur) - vec2f(x0, y0);
        immutable vec2f translatedCursor = cursor * tScale + tPos;
        this.cursor = cursor;

        //stderr.writefln!"%s;"(((translatedCursor - trTopLeft) / (trBottomRight - trTopLeft)));

        sPos = currPos;
        if (offset.y > 0.0) // zoom in
        {
            tPos = tPos - lerp(vec2f(0,0), trSize - trSize * zoomFactor, ((translatedCursor - trTopLeft) / (trBottomRight - trTopLeft)));
        }
        else if (offset.y < 0.0) // zoom out
        {
            tPos = tPos - lerp(vec2f(0,0), trSize - trSize / zoomFactor, ((translatedCursor - trTopLeft) / (trBottomRight - trTopLeft)));
        }

        sScale = currScale;
        tScale = tScale * zoomFactor ^^ offset.y;
        scaleTime = 1.0;
        posTime = 1.0;
    }

    private float currScale()
    {
        return lerp(tScale, sScale, scaleTime ^^ 2.0f);
//        return 1;
//return        tScale * (1 -scaleTime) + sScale * scaleTime;
    }

    NVGImage bg;

    private vec2f currPos()
    {
//        return vec2f(0,0);
        return lerp(tPos, sPos, posTime ^^ 2.0f);
    }
    import std.datetime;
    void progress(Duration time)
    {
        //if (posTime == 0)
        scaleTime -= time.total!"usecs" / 0.3e6f;
        if (scaleTime < 0.0)
            scaleTime = 0.0;
        posTime -= time.total!"usecs" / 0.3e6f;
        if (posTime < 0.0)
            posTime = 0.0;


    }

    void draw(NVGContext nvg)
    {
        NVGMatrix rest = nvg.currTransform;
        NVGMatrix mat = NVGMatrix().identity;
        mat = mat.translate(/+-width/2.0 + +/currPos.x,/+ -height/2.0 ++/ currPos.y);
        mat = mat.scale(1.0f/currScale, 1.0f/currScale);
        mat = mat.translate(x0/++width/2.0f+/, y0/++height/2.0f+/);

        nvg.currTransform(mat);

        nvg.beginPath();
        nvg.circle(0, 0, 100);
        nvg.fillColor(NVGColor.red);
        nvg.fill();
        nvg.clip(NVGClipMode.Replace);

        nvg.beginPath();
        nvg.circle(100, 0, 150);
        nvg.fillColor(NVGColor.green);
        nvg.fill();
        nvg.clip();

        nvg.beginPath();
        nvg.circle(20, 0, 100);
        nvg.fillColor(NVGColor.blue);
        nvg.fill();

/+        nvg.beginPath(); // start new path
        nvg.roundedRect(-256/2, -256/2, 256, 256, 10);
        nvg.fillPaint = nvg.imagePattern(-256/2, -256/2, 256, 256, 0, bg);
        nvg.fill();

        nvg.fill();
+/


        nvg.currTransform(rest);
    }

    void pointer(float x, float y)
    {}

    Draggable drag(float x, float y)
    {
        return Draggable.init;
    }

    void click(bool press, float x, float y)
    {}

    void end()
    {}

    invariant
    {
        assert(scaleTime >= 0.0);
        assert(scaleTime <= 1.0);
        assert(posTime >= 0.0);
        assert(posTime <= 1.0);
    }
}
