; p1_loop: 循环 10 次累加，验证后向分支反复跳转
; 期望：r5 = 30，mem[0] = 30
        li     r4, 0x1c100000
        li     r5, 0
        li     r6, 10
loop:
        addi.w r5, r5, 3
        addi.w r6, r6, -1
        bne    r6, r0, loop
        st.w   r5, r4, 0
        st.w   r0, r4, 0x100
done:
        b      done
