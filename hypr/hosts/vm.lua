-- vm: the QEMU test host. One virtio-gpu output, Virtual-1, with no secondary.

hl.monitor({
    output   = "Virtual-1",
    mode     = "preferred",
    position = "0x0",
    scale    = "1",
})

return {
    primary = "Virtual-1",
}
