; p5_nested: 嵌套循环，分支密度高且规律（预测器最容易受益的形态）
; 外循环 4 次 × 内循环 6 次，内层 bne 执行 24 次、外层 bne 执行 4 次
; 期望：r5 = 24 (0x18)，mem[0] = 24
        li     r4, 0x1c100000
        li     r5, 0
        li     r6, 4
outer:
        li     r7, 6
inner:
        addi.w r5, r5, 1
        addi.w r7, r7, -1
        bne    r7, r0, inner
        addi.w r6, r6, -1
        bne    r6, r0, outer
        st.w   r5, r4, 0
        st.w   r0, r4, 0x100
done:
        b      done
