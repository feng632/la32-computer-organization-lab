; p6_chain: if-else 判断链（前向条件分支 + 无条件跳）
; 被测值 r5=3 依次与 1、2、3 比较，第三次命中，r6 应为 4。
; 这条链上前两条 beq 都不跳（对 2-bit 预测器正确），第三条首次跳要纠正；
; 配合 b 跳过未命中分支，属于"收益有限但不应为负"的形态，用于对照 P5。
; 若错误路径被执行（跳转目标算错），r6 会变成 1 或 2，可被检出。
; 期望：r6 = 4，mem[0] = 4
        li     r4, 0x1c100000
        li     r5, 3
        li     r6, 0
        li     r8, 1
        beq    r5, r8, c1
        addi.w r8, r8, 1
        beq    r5, r8, c2
        addi.w r8, r8, 1
        beq    r5, r8, c3
        addi.w r6, r0, -1
        b      after
c1:
        addi.w r6, r0, 1
        b      after
c2:
        addi.w r6, r0, 2
        b      after
c3:
        addi.w r6, r0, 4
after:
        st.w   r6, r4, 0
        st.w   r0, r4, 0x100
done:
        b      done
