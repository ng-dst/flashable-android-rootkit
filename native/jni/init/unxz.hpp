#pragma once

#include <xz.h>

//  rootdir.cpp   mount.cpp
static bool unxz(int fd, const uint8_t *buf, size_t size) {
    uint8_t out[8192];
    xz_crc32_init();
    struct xz_dec *dec = xz_dec_init(XZ_DYNALLOC, 1 << 26);
    struct xz_buf b = {
            .in = buf,
            .in_pos = 0,
            .in_size = size,
            .out = out,
            .out_pos = 0,
            .out_size = sizeof(out)
    };
    enum xz_ret ret;
    do {
        ret = xz_dec_run(dec, &b);
        if (ret != XZ_OK && ret != XZ_STREAM_END)
            return false;
        write(fd, out, b.out_pos);
        b.out_pos = 0;
    } while (b.in_pos != size);
    return true;
}