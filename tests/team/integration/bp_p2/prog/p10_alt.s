; p10_alt: 交替方向（2-bit 预测器持续错预测的最坏形态）
;
; 构造：r8 在 0/1 间翻转，主分支 beq r8, r0, L1 因此交替 taken / not-taken，
;       2-bit 状态在 10/01 之间来回，每轮都预测错、每轮都要纠正。
; 判据：两条路径都执行 addi.w r6, r6, 1，因此 r6 必须正好等于 8。
;       若纠正丢指令或重复执行，r6 会偏离 8。
; 期望：r6 = 8，mem[0] = 8
        li     r4, 0x1c100000
        li     r5, 8
        li     r8, 0
        li     r6, 0
loop:
        beq    r8, r0, set1
        li     r8, 0
        b      flipped
set1:
        li     r8, 1
flipped:
        beq    r8, r0, L1
        addi.w r6, r6, 1
        b      L2
L1:
        addi.w r6, r6, 1
L2:
        addi.w r5, r5, -1
        bne    r5, r0, loop
        st.w   r6, r4, 0
        st.w   r0, r4, 0x100
done:
        b      done
