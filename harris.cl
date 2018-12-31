__constant sampler_t reflect_sampler = CLK_NORMALIZED_COORDS_FALSE | CLK_ADDRESS_MIRRORED_REPEAT | CLK_FILTER_NEAREST;
__constant sampler_t clamp_sampler = CLK_NORMALIZED_COORDS_FALSE | CLK_ADDRESS_CLAMP_TO_EDGE | CLK_FILTER_NEAREST;


__kernel void Argb32ToFloat (
	__read_only image2d_t src,
	__write_only image2d_t dest) {
    const int2 pos = {get_global_id(0), get_global_id(1)};
    const float4 in = read_imagef(src, clamp_sampler, pos);
    const float4 out;
    out.x = in.x * 0.2126f + in.y * 0.7152f + in.z * 0.0722f;
    write_imagef(dest, pos, out);
}

__kernel void Smoothing (
	__read_only image2d_t src,
	__constant float* filterWeights,
	__write_only image2d_t dest) {

    const int2 pos = {get_global_id(0), get_global_id(1)};

    float4 sum = (float4)(0.0f);
    int i = 0;
    for (int y = -HALF_SMOOTHING; y <= HALF_SMOOTHING; y++) {
        for (int x = -HALF_SMOOTHING; x <= HALF_SMOOTHING; ++x) {
            sum += filterWeights[i] * read_imagef(src, reflect_sampler, pos + (int2)(x,y));
            ++i;
        }
    }

    write_imagef(dest, (int2)(pos.x, pos.y), sum);
}

__kernel void DiffX (
	__read_only image2d_t src,
	__write_only image2d_t dest) {

    const int2 pos = {get_global_id(0), get_global_id(1)};
    float4 sum = read_imagef(src, reflect_sampler, (int2)(pos.x-1,pos.y)) - read_imagef(src, reflect_sampler, (int2)(pos.x+1,pos.y));
    write_imagef(dest, (int2)(pos.x, pos.y), sum);
}

__kernel void DiffY (
	__read_only image2d_t src,
	__write_only image2d_t dest) {

    const int2 pos = {get_global_id(0), get_global_id(1)};
    float4 sum = read_imagef(src, reflect_sampler, (int2)(pos.x,pos.y-1)) - read_imagef(src, reflect_sampler, (int2)(pos.x,pos.y+1));
    write_imagef (dest, (int2)(pos.x, pos.y), sum);
}

__kernel void Structure (
	__read_only image2d_t i_x,
	__read_only image2d_t i_y,
	__write_only image2d_t dest) {

    const int2 pos = {get_global_id(0), get_global_id(1)};
    float4 s = (float4)(0.0f);

    for (int y = -HALF_STRUCTURE; y <= HALF_STRUCTURE; y++) {
        for (int x = -HALF_STRUCTURE; x <= HALF_STRUCTURE; ++x) {
            const float s_x = read_imagef(i_x, reflect_sampler, pos + (int2)(x,y)).x;
            const float s_y = read_imagef(i_y, reflect_sampler, pos + (int2)(x,y)).x;
            s.x += s_x * s_x;
            s.y += s_x * s_y;
            s.z += s_y * s_y;
        }
    }

    write_imagef(dest, pos, s);
}

__kernel void Response (
	__read_only image2d_t src,
	__write_only image2d_t dest) {

    const int2 pos = {get_global_id(0), get_global_id(1)};

    const float4 s = read_imagef(src, reflect_sampler, pos);
    const float4 r;
    r.x = (s.x * s.z - s.y * s.y) - HARRIS_K * (s.x + s.z) * (s.x + s.z);

    write_imagef(dest, pos, r);
}

__kernel void Max (
	__read_only image2d_t src,
    __write_only image1d_t max_values) {

    const int row = get_global_id(0);
    const int width = get_image_width(src);
    float row_max = 0.0f;

    for (int x = 0; x < width; ++x) {
        const int2 pos = {x, row};
        const float4 s = read_imagef(src, reflect_sampler, pos);
        row_max = max(s.x, row_max);
    }

    write_imagef(max_values, row, row_max);
}

__kernel void NonMaxSuppression (
	__read_only image2d_t src,
    float threshold,
	__write_only image2d_t dest) {

    const int2 pos = {get_global_id(0), get_global_id(1)};
    const float4 max = read_imagef(src, reflect_sampler, pos);

    if (max.x < threshold) {
        write_imagef(dest, pos, (float4)0.0f);
        return;
    }

    for (int y = -HALF_SUPPRESSION; y <= HALF_SUPPRESSION; y++) {
        for (int x = -HALF_SUPPRESSION; x <= HALF_SUPPRESSION; ++x) {
            const float4 r = read_imagef(src, reflect_sampler, pos + (int2)(x,y));
            if (r.x > max.x) {
                write_imagef(dest, pos, (float4)0.0f);
                return;
            }
        }
    }

    write_imagef(dest, pos, max);
}
