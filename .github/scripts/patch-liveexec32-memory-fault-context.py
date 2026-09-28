#!/usr/bin/env python3
from pathlib import Path
p = Path("build/LiveExec32/HostFrameworks/LC32/dynarmic_callbacks.cpp")
s = p.read_text()
old = r'''        SetPendingGuestCrashMessage(
            "%s at guest address 0x%08x", operation, address);
'''
new = r'''        const auto registers = cpu->Regs();
        u32 queuedObject = 0;
        u32 objectWords[8] = {};
        u32 vtableWords[8] = {};
        const bool haveQueueSlot = read_guest_memory_with_permissions(
            registers[Reg::R4] + 0x98, &queuedObject,
            sizeof(queuedObject), PROT_READ);
        const bool haveObject = queuedObject &&
            read_guest_memory_with_permissions(
                queuedObject, objectWords, sizeof(objectWords), PROT_READ);
        const u32 vtable = haveObject ? objectWords[0] : 0;
        const bool haveVtable = vtable &&
            read_guest_memory_with_permissions(
                vtable, vtableWords, sizeof(vtableWords), PROT_READ);
        SetPendingGuestCrashMessage(
            "%s at guest address 0x%08x; pc=0x%08x r0=0x%08x r4=0x%08x; "
            "r4+0x98 readable=%d object=0x%08x readable=%d words="
            "[%08x %08x %08x %08x %08x %08x %08x %08x]; "
            "vtable=0x%08x readable=%d words="
            "[%08x %08x %08x %08x %08x %08x %08x %08x]",
            operation, address, registers[Reg::PC], registers[Reg::R0],
            registers[Reg::R4], haveQueueSlot, queuedObject, haveObject,
            objectWords[0], objectWords[1], objectWords[2], objectWords[3],
            objectWords[4], objectWords[5], objectWords[6], objectWords[7],
            vtable, haveVtable, vtableWords[0], vtableWords[1],
            vtableWords[2], vtableWords[3], vtableWords[4], vtableWords[5],
            vtableWords[6], vtableWords[7]);
'''
if old not in s: raise SystemExit("memory-fault context anchor missing")
p.write_text(s.replace(old, new, 1))
print("LC32: installed queued-object context for memory faults")
