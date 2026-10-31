; p8_syscall_wrong: 错误路径上的 syscall 不得触发异常
;
; 构造与 p7 相同，错误路径换成 syscall 0 + 一条改寄存器指令。
; 判据：程序正常走到结束标志（r10 = 3，mem[0] = 3）。
;       若 syscall 被错误执行，会跳向未初始化的 EENTRY，
;       程序再也写不到 0x1c100100 结束标志，TB 超时判 FAIL。
        li     r4, 0x1c100000
        li     r5, 3
        li     r10, 0
loop:
        beq    r5, r5, skip
        syscall 0
        addi.w r10, r0, 0x5ad
skip:
        addi.w r10, r10, 1
        addi.w r5, r5, -1
        bne    r5, r0, loop
        st.w   r10, r4, 0
        st.w   r0, r4, 0x100
done:
        b      done
