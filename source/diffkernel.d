@compute(CompileFor.deviceOnly) module diffkernel;

import ldc.dcompute;
import dcompute.std.index;
import app;
import cgfm.math.vector;


@kernel void CLdiffEq(ConstantPointer!Point input, GlobalPointer!Point output, uint len)
{
    auto gi = GlobalIndex.x;
    output[gi].position = vec2l(0,0);
    output[gi].momentum = vec2f(0,0);
    output[gi].position = cast(vec2l)input[gi].momentum;
    foreach (ii; 0 .. len)
    {
        if (input[gi].position == input[ii].position)
            continue;
        auto relLocL = input[ii].position - input[gi].position;
        auto relLocD = cast(vec2d)(relLocL);
        output[i].momentum +=
            relLocD.normalized * max((10000.0/((relLocD*5.0/int.max).squaredMagnitude)
                                        - 1000.0/((relLocD*5.0/int.max).squaredMagnitude ^^ 2)), -10000000.0);
    }
    output[gi].momentum -= input[gi].momentum * 0.05;
}
