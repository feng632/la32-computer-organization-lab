; p4_jirl: 间接跳转目标变化
; 第一轮走 t1，之后走 t2，同一个 lo  区里两个 jirl 站点目标不断变化。
; 期望：r5 = 1 + 2 + 2 = 5，mem[0] = 5
        li     r4, 0x1c100000
        li     r5, 0
        li     r9, 0
        la     r10, t1
        la     r11, t2
top:
        addi.w r9, r9, 1
        addi.w r12, r9, -1
        beq    r12, r0, use_t1
        jirl   r0, r11, 0
use_t1:
        jirl   r0, r10, 0
t1:
        addi.w r5, r5, 1
        b      after
t2:
        addi.w r5, r5, 2
after:
        addi.w r12, r9, -3
        bne    r12, r0, top
        st.w   r5, r4, 0
        st.w   r0, r4, 0x100
done:
        b      done
