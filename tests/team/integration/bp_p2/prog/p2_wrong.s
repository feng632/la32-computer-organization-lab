; p2_wrong: 错误路径副作用
; beq 恒成立，紧随其后的两条指令属于错误路径：一条改寄存器、一条写内存。
; 若错误路径被执行过，r8 会变成 0x7f7、mem[1] 会被写成 0x7f7。
; 期望：mem[0] = 0xdead，mem[1] = 0
        li     r4, 0x1c100000
        li     r8, 0xdead
        li     r9, 1
        beq    r9, r9, skip
        addi.w r8, r0, 0x7f7
        st.w   r8, r4, 4
skip:
        st.w   r8, r4, 0
        st.w   r0, r4, 0x100
done:
        b      done
