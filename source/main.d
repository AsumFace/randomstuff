import bindbc.glfw;
import bindbc.opengl;
//import arsd.simpledisplay;
import arsd.nanovega;
import std.stdio;
import core.thread;
import std.string;

void main()
{
    if (glfwInit == false)
        assert(0, "GLFW initialization failed");
    else
        writefln!"GLFW initialized!";

    glfwSetErrorCallback(&error_callback);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 2);
    glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, GL_TRUE);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    immutable int width = 800;
    immutable int height = 600;
    GLFWwindow* window = glfwCreateWindow(width, height, "NanoVega Test", null, null);
    if (window is null)
    {
        assert(0, "GLFW window creation failure");
    }
    else
        stderr.writefln!"GLFW window created!";
    scope(exit) glfwDestroyWindow(window);
    glfwMakeContextCurrent(window);

    NVGContext nvg = nvgCreateContext();
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

    import core.thread;
    bool exit = false;
    auto expiration = MonoTime.currTime + 3000000.msecs;
    while (!exit)
    {
        glClearColor(0, 0, 0, 0);
        glClear(glNVGClearFlags);
        {
            nvg.beginFrame(width, height);
            scope(exit) nvg.endFrame();
            nvg.beginPath();
            double xpos;
            double ypos;
            glfwGetCursorPos(window, &xpos, &ypos);
            nvg.roundedRect(width/2, height/2, xpos - width/2, ypos - height/2, 10);

            nvg.fillPaint = nvg.linearGradient(0, 0, width, height, NVGColor("#f70"), NVGColor.green);
            nvg.fill();
            nvg.strokeColor = NVGColor.white;
            nvg.strokeWidth = 2;
            nvg.stroke();
        }
        glfwSwapBuffers(window);
        if (MonoTime.currTime > expiration)
            exit = true;
    }
}
