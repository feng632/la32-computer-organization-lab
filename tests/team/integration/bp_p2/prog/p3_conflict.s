; p3_conflict: 连续分支 + 同索引冲突
; 三处 b 连续出现；其中 0x1c000100 处的 b 与 0x1c000000 附近的 b
; 索引同为 PC[7:2]=0、tag 不同，用来构造预测表同索引冲突。
; 期望：r5 = 7，mem[0] = 7
        li     r4, 0x1c100000
        li     r5, 0
        b      c1
c1:
        addi.w r5, r5, 1
        b      c2
c2:
        addi.w r5, r5, 2
        b      c3
        .org   0x1c000100
c3:
        addi.w r5, r5, 4
        st.w   r5, r4, 0
        st.w   r0, r4, 0x100
done:
        b      done
